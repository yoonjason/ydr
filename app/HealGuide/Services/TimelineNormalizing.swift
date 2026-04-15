protocol TimelineNormalizing {
    func normalize(playerCasts: [CastEvent], bossCasts: [CastEvent], windowSeconds: Double) -> [TimelineEntry]
}
