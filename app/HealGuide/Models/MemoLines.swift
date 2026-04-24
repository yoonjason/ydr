import Foundation

enum ColorPreset: String, CaseIterable, Equatable {
    case white, yellow, orange, red, cyan, green

    var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .white:  return (1.0, 1.0, 1.0)
        case .yellow: return (1.0, 0.9, 0.2)
        case .orange: return (1.0, 0.6, 0.1)
        case .red:    return (1.0, 0.3, 0.3)
        case .cyan:   return (0.3, 0.9, 1.0)
        case .green:  return (0.4, 1.0, 0.4)
        }
    }

    static func nearest(r: Double, g: Double, b: Double) -> ColorPreset {
        allCases.min { lhs, rhs in
            lhs.squaredDistance(r: r, g: g, b: b) < rhs.squaredDistance(r: r, g: g, b: b)
        } ?? .white
    }

    private func squaredDistance(r: Double, g: Double, b: Double) -> Double {
        let dr = rgb.r - r
        let dg = rgb.g - g
        let db = rgb.b - b
        return dr * dr + dg * dg + db * db
    }
}

struct MemoContent: Equatable {
    var lines: [String] = []
    var fontSize: Int = 14
    var fontColor: ColorPreset = .white
    var bgAlpha: Int = 60
}
