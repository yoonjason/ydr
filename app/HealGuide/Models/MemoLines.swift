import Foundation

enum ColorPreset: String, CaseIterable, Equatable {
    case white, yellow, orange, red, cyan, green

    var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .white:  return (1.0, 1.0, 1.0)
        case .yellow: return (1.0, 1.0, 0.0)
        case .orange: return (1.0, 0.5, 0.0)
        case .red:    return (1.0, 0.2, 0.2)
        case .cyan:   return (0.0, 1.0, 1.0)
        case .green:  return (0.4, 1.0, 0.2)
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

struct MemoContent {
    var lines: [String] = []
    var fontSize: Int = 14
    var fontColor: ColorPreset = .white
    var bgAlpha: Int = 60
    var updatedAt: Int = 0
}

extension MemoContent: Equatable {
    // updatedAt은 저장 시각마다 달라지므로 Equatable 에서 제외
    static func == (lhs: MemoContent, rhs: MemoContent) -> Bool {
        lhs.lines == rhs.lines &&
        lhs.fontSize == rhs.fontSize &&
        lhs.fontColor == rhs.fontColor &&
        lhs.bgAlpha == rhs.bgAlpha
    }
}

struct MemoBundle {
    var shared: MemoContent
    var characters: [String: MemoContent]
    var updatedAt: Int

    init(
        shared: MemoContent = MemoContent(),
        characters: [String: MemoContent] = [:],
        updatedAt: Int = 0
    ) {
        self.shared = shared
        self.characters = characters
        self.updatedAt = updatedAt
    }
}

extension MemoBundle: Equatable {
    // updatedAt 제외
    static func == (lhs: MemoBundle, rhs: MemoBundle) -> Bool {
        lhs.shared == rhs.shared &&
        lhs.characters == rhs.characters
    }
}
