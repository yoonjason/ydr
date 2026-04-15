final class MockTimelineNormalizer: TimelineNormalizing {
    var result: [TimelineEntry] = []

    func normalize(playerCasts: [CastEvent], bossCasts: [CastEvent], windowSeconds: Double) -> [TimelineEntry] {
        result
    }
}
