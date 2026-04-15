struct TimelineNormalizer: TimelineNormalizing {
    // 램프(사전 준비) 윈도우 — 보스 캐스트 이전 몇 초까지의 플레이어 시퀀스를 leadIn 으로 기록
    private static let leadInWindowSeconds: Double = 15.0

    func normalize(
        encounterStart: Int64,
        encounterEnd: Int64,
        bossCasts: [CastEvent],
        playerCasts: [CastEvent],
        maxWindow: Double
    ) -> (absolute: [AbsoluteEntry], reactions: [ReactionEntry], leadIns: [LeadInEntry]) {
        // absolute: 레퍼런스 로그에서 힐러가 실제로 쓴 플레이어 캐스트의 encounterStart 기준 오프셋.
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

        // leadIns: 각 보스 캐스트 이전 N초 윈도우 내 플레이어 캐스트를 시간순으로 수집.
        // 애드온은 네이티브 타임라인으로 "보스가 곧 시전" 정보를 받으면 이 시퀀스를 역산 예약.
        let leadInWindowMs = Int64(Self.leadInWindowSeconds * 1000)
        var leadIns: [LeadInEntry] = []
        for boss in bossCasts {
            let windowStart = boss.timestamp - leadInWindowMs
            let preCasts = playerCasts
                .filter { $0.timestamp >= windowStart && $0.timestamp < boss.timestamp }
                .sorted { $0.timestamp < $1.timestamp }
            for player in preCasts {
                leadIns.append(LeadInEntry(
                    bossAbilityID: boss.spellID,
                    playerSpellID: player.spellID,
                    offset: Double(player.timestamp - boss.timestamp) / 1000.0  // 음수
                ))
            }
        }

        return (absolute, reactions, leadIns)
    }
}
