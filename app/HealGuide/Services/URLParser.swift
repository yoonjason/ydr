import Foundation

struct URLParser: URLParsing {
    // https://www.warcraftlogs.com/reports/<code>#fight=<N>&source=<N>
    // https://www.warcraftlogs.com/reports/<code>?fight=<N>&source=<N>
    private static let codePattern = #/reports/([A-Za-z0-9]{8,16})/#

    func parse(_ rawURL: String) throws -> ReportURL {
        guard let urlComponents = URLComponents(string: rawURL) else {
            throw AppError.invalidURL
        }

        // www.warcraftlogs.com / ko.warcraftlogs.com / fr.warcraftlogs.com 등 로케일 서브도메인 허용
        guard let host = urlComponents.host,
              host == "warcraftlogs.com" || host.hasSuffix(".warcraftlogs.com") else {
            throw AppError.invalidURL
        }

        let path = urlComponents.path
        guard let match = path.firstMatch(of: Self.codePattern) else {
            throw AppError.invalidURL
        }

        let code = String(match.1)

        // fragment(#) 또는 query(?) 양쪽에서 fight/source 파싱
        var params: [String: String] = [:]

        if let fragment = urlComponents.fragment, !fragment.isEmpty {
            params = parseQueryItems(from: fragment)
        }

        if let queryItems = urlComponents.queryItems {
            for item in queryItems {
                if let value = item.value {
                    params[item.name] = value
                }
            }
        }

        guard let fightValue = params["fight"] else {
            throw AppError.invalidURL
        }
        guard fightValue != "last" else {
            throw AppError.fightSelectionRequired
        }
        guard let fightID = Int(fightValue) else {
            throw AppError.invalidURL
        }

        guard let sourceValue = params["source"], let sourceID = Int(sourceValue) else {
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
