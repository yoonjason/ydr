import Foundation

protocol WoWCharacterScannerProtocol: Sendable {
    func scan(wowAddonsPath: String) -> [WoWCharacter]
    func scanWithDiagnostic(wowAddonsPath: String) -> (characters: [WoWCharacter], message: String?)
}

struct WoWCharacter: Hashable, Sendable {
    let realm: String
    let name: String

    var key: String { "\(name)-\(realm.replacingOccurrences(of: " ", with: ""))" }
}

struct WoWCharacterScanner: WoWCharacterScannerProtocol {
    func scan(wowAddonsPath: String) -> [WoWCharacter] {
        guard !wowAddonsPath.isEmpty else { return [] }

        // AddOns → Interface → _retail_ (client root)
        let addonsURL = URL(fileURLWithPath: wowAddonsPath, isDirectory: true)
        let clientURL = addonsURL
            .deletingLastPathComponent()  // Interface
            .deletingLastPathComponent()  // _retail_

        let wtfAccountURL = clientURL.appendingPathComponent("WTF/Account")

        let fm = FileManager.default
        guard fm.fileExists(atPath: wtfAccountURL.path) else { return [] }

        var characters: [WoWCharacter] = []
        var seen = Set<String>()

        guard let accounts = try? fm.contentsOfDirectory(
            at: wtfAccountURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        for accountURL in accounts {
            guard isDirectory(accountURL),
                  accountURL.lastPathComponent != "SavedVariables" else { continue }

            guard let realms = try? fm.contentsOfDirectory(
                at: accountURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            ) else { continue }

            for realmURL in realms {
                guard isDirectory(realmURL),
                      realmURL.lastPathComponent != "SavedVariables" else { continue }

                let realmName = realmURL.lastPathComponent

                guard let chars = try? fm.contentsOfDirectory(
                    at: realmURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: .skipsHiddenFiles
                ) else { continue }

                for charURL in chars {
                    guard isDirectory(charURL) else { continue }
                    let charName = charURL.lastPathComponent
                    let healGuideLua = charURL
                        .appendingPathComponent("SavedVariables")
                        .appendingPathComponent("HealGuide.lua")
                    guard fm.fileExists(atPath: healGuideLua.path) else { continue }

                    let character = WoWCharacter(realm: realmName, name: charName)
                    if seen.insert(character.key).inserted {
                        characters.append(character)
                    }
                }
            }
        }

        return characters.sorted { $0.key < $1.key }
    }

    func scanWithDiagnostic(wowAddonsPath: String) -> (characters: [WoWCharacter], message: String?) {
        guard !wowAddonsPath.isEmpty else {
            return ([], "WoW AddOns 경로가 비어 있습니다.")
        }
        let wtfAccountURL = URL(fileURLWithPath: wowAddonsPath, isDirectory: true)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WTF/Account")
        guard FileManager.default.fileExists(atPath: wtfAccountURL.path) else {
            return ([], "WTF/Account 폴더를 찾을 수 없습니다.")
        }
        let characters = scan(wowAddonsPath: wowAddonsPath)
        if characters.isEmpty {
            return (characters, "HealGuide가 설치된 캐릭터를 찾을 수 없습니다.")
        }
        return (characters, nil)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
