final class MockTimelineNormalizer: TimelineNormalizing {
    var result: (absolute: [AbsoluteEntry], reactions: [ReactionEntry], leadIns: [LeadInEntry]) = ([], [], [])

    func normalize(
        encounterStart: Int64,
        encounterEnd: Int64,
        bossCasts: [CastEvent],
        playerCasts: [CastEvent],
        maxWindow: Double
    ) -> (absolute: [AbsoluteEntry], reactions: [ReactionEntry], leadIns: [LeadInEntry]) {
        result
    }
}
