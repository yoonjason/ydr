struct TimelineNormalizer: TimelineNormalizing {
    func normalize(
        encounterStart: Int64,
        encounterEnd: Int64,
        bossCasts: [CastEvent],
        playerCasts: [CastEvent],
        maxWindow: Double
    ) -> (absolute: [AbsoluteEntry], reactions: [ReactionEntry]) {
        let absolute = bossCasts.map { boss in
            AbsoluteEntry(
                spellID: boss.spellID,
                offset: Double(boss.timestamp - encounterStart) / 1000.0
            )
        }

        let maxWindowMs = Int64(maxWindow * 1000)
        var reactions: [ReactionEntry] = []
        for boss in bossCasts {
            let windowEnd = boss.timestamp + maxWindowMs
            for player in playerCasts
            where player.timestamp >= boss.timestamp && player.timestamp <= windowEnd {
                reactions.append(ReactionEntry(
                    bossAbilityID: boss.spellID,
                    playerSpellID: player.spellID,
                    delay: Double(player.timestamp - boss.timestamp) / 1000.0
                ))
            }
        }

        return (absolute, reactions)
    }
}
