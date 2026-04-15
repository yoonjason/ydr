struct TimelineNormalizer: TimelineNormalizing {
    func normalize(playerCasts: [CastEvent], bossCasts: [CastEvent], windowSeconds: Double) -> [TimelineEntry] {
        let windowMs = Int64(windowSeconds * 1000)
        var entries: [TimelineEntry] = []

        for bossCast in bossCasts {
            let windowEnd = bossCast.timestamp + windowMs
            for playerCast in playerCasts where playerCast.timestamp >= bossCast.timestamp && playerCast.timestamp <= windowEnd {
                let delay = Double(playerCast.timestamp - bossCast.timestamp) / 1000.0
                entries.append(TimelineEntry(
                    bossSpellID: bossCast.spellID,
                    playerSpellID: playerCast.spellID,
                    delay: delay
                ))
            }
        }

        return entries
    }
}
