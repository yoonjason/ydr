struct TimelineEntry: Equatable {
    let bossSpellID: Int
    let playerSpellID: Int
    let delay: Double  // seconds from boss cast to player cast
}
