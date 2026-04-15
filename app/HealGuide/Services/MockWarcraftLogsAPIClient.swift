final class MockWarcraftLogsAPIClient: WarcraftLogsAPIClient {
    var tokenResult: Result<String, AppError> = .success("mock-token")
    var fightResult: Result<FightMeta, AppError> = .success(
        FightMeta(id: 1, encounterID: 2599, name: "Mock Boss", startTime: 0, endTime: 10000, kill: true)
    )
    var castsResult: Result<[CastEvent], AppError> = .success([])

    func fetchAccessToken(clientID: String, clientSecret: String) async throws -> String {
        try tokenResult.get()
    }

    func fetchFight(reportCode: String, fightID: Int, token: String) async throws -> FightMeta {
        try fightResult.get()
    }

    func fetchCasts(reportCode: String, fightID: Int, sourceID: Int?, hostilityType: HostilityType, token: String) async throws -> [CastEvent] {
        try castsResult.get()
    }
}
