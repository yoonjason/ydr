protocol TimelineNormalizing {
    func normalize(
        encounterStart: Int64,
        encounterEnd: Int64,
        bossCasts: [CastEvent],
        playerCasts: [CastEvent],
        maxWindow: Double
    ) -> (absolute: [AbsoluteEntry], reactions: [ReactionEntry])
}
