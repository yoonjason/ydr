import Foundation

enum AppError: LocalizedError, Equatable {
    case invalidURL
    case fightSelectionRequired
    case authenticationFailed
    case networkError(String)
    case fightNotFound
    case noBossEncounters
    case noHealers
    case decodingFailed
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "유효하지 않은 URL입니다. WarcraftLogs 리포트 URL을 확인해 주세요."
        case .fightSelectionRequired:
            return "특정 전투를 선택해 주세요. WarcraftLogs에서 분석할 전투를 클릭한 후 URL을 복사해 주세요."
        case .authenticationFailed:
            return "인증에 실패했습니다. API 키를 다시 확인해 주세요."
        case .networkError(let message):
            return "네트워크 오류가 발생했습니다: \(message)"
        case .fightNotFound:
            return "해당 전투를 찾을 수 없습니다."
        case .noBossEncounters:
            return "보스 조우를 찾을 수 없습니다. 전투에 보스가 포함돼 있는지 확인해 주세요."
        case .noHealers:
            return "이 전투에서 힐러를 찾을 수 없습니다. 힐러가 포함된 전투인지 확인해 주세요."
        case .decodingFailed:
            return "데이터 파싱에 실패했습니다."
        case .keychainError(let status):
            switch status {
            case errSecAuthFailed: return "Keychain 인증에 실패했습니다."
            case errSecInteractionNotAllowed: return "Keychain에 접근할 수 없습니다."
            case errSecItemNotFound: return "Keychain 항목을 찾을 수 없습니다."
            default: return "Keychain 오류가 발생했습니다."
            }
        }
    }
}
