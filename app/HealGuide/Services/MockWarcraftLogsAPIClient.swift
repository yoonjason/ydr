// 테스트 주입용 stub. 변이 가능한 Result 필드를 보유하므로 컴파일러가 합성하는
// Sendable 을 못 받음. @unchecked Sendable 로 수동 선언 — 테스트 환경에서만
// 사용되고 프로덕션 actor 경계를 넘지 않는 전제.
final class MockWarcraftLogsAPIClient: WarcraftLogsAPIClient, @unchecked Sendable {
    var tokenResult: Result<String, AppError> = .success("mock-token")
    var encountersResult: Result<(String, [BossWindow]), AppError> = .success((
        "Mock Dungeon",
        [BossWindow(encounterID: 2599, name: "Mock Boss", startTime: 0, endTime: 10000)]
    ))
    var castsResult: Result<[CastEvent], AppError> = .success([])
    var playerDetailsResult: Result<[HealerCandidate], AppError> = .success([
        HealerCandidate(id: 330, name: "MockHealer", className: "Priest", specName: "Discipline", server: nil)
    ])
    var masterDataResult: Result<[MasterDataAbility], AppError> = .success([])
    var talentImportCodeResult: Result<String?, AppError> = .success(nil)
    var encounterNameResult: Result<String?, AppError> = .success(nil)
    var currentPartitionResult: Result<Int?, AppError> = .success(nil)

    func fetchAccessToken(clientID: String, clientSecret: String) async throws -> String {
        try tokenResult.get()
    }

    func fetchEncounters(reportCode: String, fightID: Int, token: String) async throws -> (dungeonName: String, windows: [BossWindow]) {
        let (name, windows) = try encountersResult.get()
        return (dungeonName: name, windows: windows)
    }

    func fetchPlayerDetails(reportCode: String, fightID: Int, token: String) async throws -> [HealerCandidate] {
        try playerDetailsResult.get()
    }

    func fetchCasts(
        reportCode: String,
        fightID: Int,
        sourceID: Int?,
        hostilityType: HostilityType,
        startTime: Int64,
        endTime: Int64,
        token: String
    ) async throws -> [CastEvent] {
        try castsResult.get()
    }

    func fetchMasterData(reportCode: String, token: String) async throws -> [MasterDataAbility] {
        try masterDataResult.get()
    }

    func fetchTalentImportCode(reportCode: String, fightID: Int, actorID: Int, token: String) async throws -> String? {
        try talentImportCodeResult.get()
    }

    func fetchEncounterName(encounterID: Int, token: String) async throws -> String? {
        try encounterNameResult.get()
    }

    func fetchCurrentMythicPlusPartition(encounterID: Int, token: String) async throws -> Int? {
        try currentPartitionResult.get()
    }
}
