struct JournalInstanceInfo: Equatable {
    let instanceID: Int
    let name: String
    let encounters: [JournalEncounterSummary]
}

struct JournalEncounterSummary: Equatable {
    let encounterID: Int
    let name: String
}
