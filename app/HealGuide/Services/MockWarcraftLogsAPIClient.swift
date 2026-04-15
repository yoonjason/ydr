final class MockWarcraftLogsAPIClient: WarcraftLogsAPIClient {
    var tokenResult: Result<String, AppError> = .success("mock-token")
    var encountersResult: Result<[BossWindow], AppError> = .success([
        BossWindow(encounterID: 2599, name: "Mock Boss", startTime: 0, endTime: 10000)
    ])
    var castsResult: Result<[CastEvent], AppError> = .success([])

    func fetchAccessToken(clientID: String, clientSecret: String) async throws -> String {
        try tokenResult.get()
    }

    func fetchEncounters(reportCode: String, fightID: Int, token: String) async throws -> [BossWindow] {
        try encountersResult.get()
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
}
