struct TimelineNormalizer: TimelineNormalizing {
    func normalize(
        encounterStart: Int64,
        encounterEnd: Int64,
        bossCasts: [CastEvent],
        playerCasts: [CastEvent],
        maxWindow: Double
    ) -> (absolute: [AbsoluteEntry], reactions: [ReactionEntry]) {
        // absolute: 레퍼런스 로그에서 힐러가 실제로 쓴 플레이어 캐스트의 encounterStart 기준 오프셋.
        // 애드온이 이 오프셋에 맞춰 "해당 플레이어 스킬을 쓰라" 고 알림.
        let absolute = playerCasts.map { player in
            AbsoluteEntry(
                spellID: player.spellID,
                offset: Double(player.timestamp - encounterStart) / 1000.0
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
