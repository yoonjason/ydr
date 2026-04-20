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
        state = .idle
        lastCopyFeedback = nil
    }

    // MARK: - Collect

    func collect() async {
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
            state = .failure("액세스 토큰 발급 실패: \(error.localizedDescription)")
            return
        }

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
            state = .failure("characterRankings 조회 실패: \(error.localizedDescription)")
            return
        }

        if parses.isEmpty {
            state = .failure("KR 서버에서 해당 조건의 랭킹 데이터가 없습니다.")
            return
        }

        // 3. 파스별 actor ID → talentImportCode 조회
        var samples: [TalentImportSample] = []
        for (index, parse) in parses.enumerated() {
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
                    token:         token
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

        // 4. 완전 동일 importCode 그룹핑 → 빈도 내림차순
        let grouped = Dictionary(grouping: samples, by: \.importCode)
        let groups = grouped.map { (code, samples) -> TalentBuildGroup in
            TalentBuildGroup(
                importCode:     code,
                usageCount:     samples.count,
                totalSamples:   samples.count,
                characterNames: samples.map(\.characterName)
            )
        }
        .map { group -> TalentBuildGroup in
            TalentBuildGroup(
                importCode:     group.importCode,
                usageCount:     group.usageCount,
                totalSamples:   samples.count,
                characterNames: group.characterNames
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

    func copyImportCode(_ code: String) {
        pasteboard.write(code)
        lastCopyFeedback = "복사 완료 — WoW 탤런트 창에서 붙여넣기 하세요."
    }

    // MARK: - Private

    // PlayerDetails 에서 characterName 이 일치하는 actor 의 ID 획득.
    private func resolveActorID(
        reportCode:    String,
        fightID:       Int,
        characterName: String,
        token:         String
    ) async throws -> Int? {
        let players = try await apiClient.fetchPlayerDetails(
            reportCode: reportCode, fightID: fightID, token: token
        )
        // 이름 정확 일치 우선, 실패 시 스펙 매칭으로 폴백
        if let exact = players.first(where: { $0.name == characterName }) {
            return exact.id
        }
        let specMatched = players.first {
            $0.className == selectedSpec.warcraftLogsClassName &&
            $0.specName  == selectedSpec.warcraftLogsSpecName
        }
        return specMatched?.id
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
