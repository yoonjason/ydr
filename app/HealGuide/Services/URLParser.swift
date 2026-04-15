import Foundation

struct URLParser: URLParsing {
    // https://www.warcraftlogs.com/reports/<code>#fight=<N>&source=<N>
    private static let codePattern = #/reports/([A-Za-z0-9]{8,16})/#

    func parse(_ rawURL: String) throws -> ReportURL {
        guard let urlComponents = URLComponents(string: rawURL) else {
            throw AppError.invalidURL
        }

        guard urlComponents.host == "www.warcraftlogs.com" else {
            throw AppError.invalidURL
        }

        let path = urlComponents.path
        guard let match = path.firstMatch(of: Self.codePattern) else {
            throw AppError.invalidURL
        }

        let code = String(match.1)

        guard let fragment = urlComponents.fragment, !fragment.isEmpty else {
            throw AppError.invalidURL
        }

        let fragmentItems = parseQueryItems(from: fragment)

        guard let fightValue = fragmentItems["fight"] else {
            throw AppError.invalidURL
        }
        guard fightValue != "last" else {
            throw AppError.fightSelectionRequired
        }
        guard let fightID = Int(fightValue) else {
            throw AppError.invalidURL
        }

        // source 파라미터는 필수 — 힐러 액터 식별에 필요
        guard let sourceValue = fragmentItems["source"], let sourceID = Int(sourceValue) else {
            throw AppError.invalidURL
        }

        return ReportURL(code: code, fightID: fightID, sourceID: sourceID)
    }

    private func parseQueryItems(from fragment: String) -> [String: String] {
        var items: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            items[String(parts[0])] = String(parts[1])
        }
        return items
    }
}
