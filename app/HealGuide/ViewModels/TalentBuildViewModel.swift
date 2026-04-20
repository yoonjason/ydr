import Foundation
import AppKit
import os

@MainActor
final class TalentBuildViewModel: ObservableObject {

    // MARK: - ViewState

    enum ViewState: Equatable {
        case idle
        case collecting(completed: Int, total: Int, currentName: String)
        case success(TalentBuildCollectionResult)
        case failure(String)
    }

    // MARK: - Input

    @Published var selectedDungeon:    DungeonInfo?     = DungeonInfo.currentSeason.first
    @Published var selectedDifficulty: RankerDifficulty = .mythicPlus
    @Published var selectedSpec:       HealerSpec       = .discPriest
    @Published var topNCount:          TopNCount        = .ten

    @Published var clientID:     String = ""
    @Published var clientSecret: String = ""

    @Published private(set) var state: ViewState = .idle
    @Published var lastCopyFeedback: String?

    // MARK: - Dependencies

    private let apiClient:      any WarcraftLogsAPIClient
    private let rankingService: any CharacterRankingsService
    private let pasteboard:     any PasteboardWriting
    private let keychain:       any KeychainStoring
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "TalentBuildVM")

    // 수집 Task 참조. '중지' 버튼으로 취소.
    private var collectTask: Task<Void, Never>?

    init(
        apiClient:      any WarcraftLogsAPIClient    = WarcraftLogsAPIClientImpl(),
        rankingService: any CharacterRankingsService = CharacterRankingsServiceImpl(),
        pasteboard:     any PasteboardWriting            = SystemPasteboard(),
        keychain:       any KeychainStoring          = FileCredentialStore()
    ) {
        self.apiClient      = apiClient
        self.rankingService = rankingService
        self.pasteboard     = pasteboard
        self.keychain       = keychain
    }

    // MARK: - Lifecycle

    func onAppear() {
        if clientID.isEmpty, let id = keychain.loadClientID() {
            clientID = id
        }
        if clientSecret.isEmpty, let secret = keychain.load() {
            clientSecret = secret
        }
    }

    func reset() {
        collectTask?.cancel()
        collectTask = nil
        state = .idle
        lastCopyFeedback = nil
    }

    // MARK: - Collect

    // View 에서 호출하는 진입점. 이전 Task 취소 후 새로 시작.
    func startCollect() {
        collectTask?.cancel()
        collectTask = Task { [weak self] in
            await self?.collect()
            self?.collectTask = nil
        }
    }

    // 진행 중인 수집 취소. state 는 idle 로 복귀.
    func cancelCollect() {
        collectTask?.cancel()
        collectTask = nil
        state = .idle
        lastCopyFeedback = nil
    }

    private func collect() async {
        guard let dungeon = selectedDungeon else { return }
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            state = .failure("WarcraftLogs Client ID / Secret 을 입력해주세요. (로그 분석 탭에서 설정한 값이 자동 로드됩니다)")
            return
        }

        state = .collecting(completed: 0, total: topNCount.rawValue, currentName: "인증 중...")

        // 1. 토큰
        let token: String
        do {
            token = try await apiClient.fetchAccessToken(clientID: clientID, clientSecret: clientSecret)
        } catch {
            if Task.isCancelled { state = .idle; return }
            state = .failure("액세스 토큰 발급 실패: \(error.localizedDescription)")
            return
        }
        if Task.isCancelled { state = .idle; return }

        // 2. characterRankings
        state = .collecting(completed: 0, total: topNCount.rawValue, currentName: "랭킹 조회 중...")
        let parses: [RankerParse]
        do {
            parses = try await rankingService.fetchCharacterRankings(
                encounterId:  dungeon.id,
                className:    selectedSpec.warcraftLogsClassName,
                specName:     selectedSpec.warcraftLogsSpecName,
                difficulty:   selectedDifficulty.warcraftLogsID,
                serverRegion: "KR",
                limit:        topNCount.rawValue,
                token:        token
            )
        } catch {
            if Task.isCancelled { state = .idle; return }
            state = .failure("characterRankings 조회 실패: \(error.localizedDescription)")
            return
        }
        if Task.isCancelled { state = .idle; return }

        if parses.isEmpty {
            state = .failure("KR 서버에서 해당 조건의 랭킹 데이터가 없습니다.")
            return
        }

        // 3. 파스별 actor ID → talentImportCode 조회
        // playerDetails 는 (reportCode, fightID) 가 같으면 동일 응답이므로 세션 내 캐싱
        var samples: [TalentImportSample] = []
        var playerDetailsCache: [String: [HealerCandidate]] = [:]

        for (index, parse) in parses.enumerated() {
            if Task.isCancelled { state = .idle; return }
            state = .collecting(
                completed:   index,
                total:       parses.count,
                currentName: "\(parse.characterName) 탤런트 조회 중..."
            )

            do {
                let actorID = try await resolveActorID(
                    reportCode:    parse.reportCode,
                    fightID:       parse.fightID,
                    characterName: parse.characterName,
                    token:         token,
                    cache:         &playerDetailsCache
                )
                guard let actorID else { continue }

                let importCode = try await apiClient.fetchTalentImportCode(
                    reportCode: parse.reportCode,
                    fightID:    parse.fightID,
                    actorID:    actorID,
                    token:      token
                )
                if let importCode, !importCode.isEmpty {
                    samples.append(TalentImportSample(
                        reportCode:    parse.reportCode,
                        fightID:       parse.fightID,
                        characterName: parse.characterName,
                        importCode:    importCode
                    ))
                }
            } catch {
                logger.warning("\(parse.reportCode)/\(parse.fightID) 탤런트 조회 실패, 스킵: \(error)")
                continue
            }
        }

        if samples.isEmpty {
            state = .failure("탤런트 export 문자열을 획득한 파스가 없습니다. WCL 리포트에 탤런트 정보가 기록되지 않았을 수 있습니다.")
            return
        }

        if Task.isCancelled { state = .idle; return }

        // 4. 완전 동일 importCode 그룹핑 → 빈도 내림차순
        let totalSamples = samples.count
        let grouped = Dictionary(grouping: samples, by: \.importCode)
        let groups = grouped.map { (code, groupSamples) in
            TalentBuildGroup(
                importCode:   code,
                samples:      groupSamples,
                totalSamples: totalSamples
            )
        }
        .sorted { $0.usageCount > $1.usageCount }

        state = .success(TalentBuildCollectionResult(
            spec:            selectedSpec,
            dungeonName:     dungeon.name,
            difficulty:      selectedDifficulty,
            collectedAt:     Date(),
            totalSamples:    samples.count,
            requestedRankers: topNCount.rawValue,
            groups:          groups
        ))
    }

    // MARK: - Clipboard

    func copyImportCode(_ code: String, rank: Int) {
        pasteboard.write(code)
        lastCopyFeedback = "#\(rank) 빌드 복사 완료 — WoW 탤런트 창에서 붙여넣기 하세요."
    }

    // MARK: - Private

    // PlayerDetails 에서 characterName 이 일치하는 actor 의 ID 획득.
    // cache: 동일 (reportCode, fightID) 에 대한 중복 네트워크 호출 방지.
    private func resolveActorID(
        reportCode:    String,
        fightID:       Int,
        characterName: String,
        token:         String,
        cache:         inout [String: [HealerCandidate]]
    ) async throws -> Int? {
        let key = "\(reportCode)/\(fightID)"
        let players: [HealerCandidate]
        if let cached = cache[key] {
            players = cached
        } else {
            players = try await apiClient.fetchPlayerDetails(
                reportCode: reportCode, fightID: fightID, token: token
            )
            cache[key] = players
        }

        // WCL 의 characterName 과 playerDetails.name 은 '캐릭터명-서버명' 포함
        // 여부가 케이스마다 달라 서버명을 제거한 베이스 이름으로 비교한다.
        let targetBase = baseName(characterName)
        if let exact = players.first(where: { baseName($0.name) == targetBase }) {
            return exact.id
        }
        // 이름 매칭 실패 시 스펙 매칭으로 폴백
        let specMatched = players.first {
            $0.className == selectedSpec.warcraftLogsClassName &&
            $0.specName  == selectedSpec.warcraftLogsSpecName
        }
        return specMatched?.id
    }

    private func baseName(_ raw: String) -> String {
        raw.components(separatedBy: "-").first ?? raw
    }

    // MARK: - Derived

    var availableDungeons: [DungeonInfo] {
        switch selectedDifficulty {
        case .mythicPlus:           return DungeonInfo.currentSeason
        case .heroic, .normal:      return DungeonInfo.currentSeason.filter { $0.supportsNormalHeroic }
        }
    }

    func resetDungeonSelectionIfNeeded() {
        guard let current = selectedDungeon else { return }
        if !availableDungeons.contains(current) {
            selectedDungeon = availableDungeons.first
        }
    }
}
