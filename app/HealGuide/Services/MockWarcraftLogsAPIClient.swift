final class MockWarcraftLogsAPIClient: WarcraftLogsAPIClient {
    var tokenResult: Result<String, AppError> = .success("mock-token")
    var encountersResult: Result<(String, [BossWindow]), AppError> = .success((
        "Mock Dungeon",
        [BossWindow(encounterID: 2599, name: "Mock Boss", startTime: 0, endTime: 10000)]
    ))
    var castsResult: Result<[CastEvent], AppError> = .success([])

    func fetchAccessToken(clientID: String, clientSecret: String) async throws -> String {
        try tokenResult.get()
    }

    func fetchEncounters(reportCode: String, fightID: Int, token: String) async throws -> (dungeonName: String, windows: [BossWindow]) {
        let (name, windows) = try encountersResult.get()
        return (dungeonName: name, windows: windows)
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
