import SwiftUI

struct MemoEditorTab: View {
    @StateObject private var viewModel = MemoEditorViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                pathSection
                editorSection
                settingsSection
                Divider()
                actionRow
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 420)
        .onAppear { viewModel.onAppear() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Label("상시 메모", systemImage: "note.text")
                    .font(.headline)
                Text("인게임 애드온과 공유되는 메모입니다. 저장하면 HGPT_Memo.lua 에 기록됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("애드온에서도 편집 가능하며, /reload 직후에는 SavedVariables(HealGuideDB.memo)가 우선합니다.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var pathSection: some View {
        if viewModel.wowAddonsPath.isEmpty {
            GroupBox {
                Label("WoW AddOns 경로가 설정되어 있지 않습니다. 로그 분석 또는 랭커 수집 탭에서 경로를 먼저 설정하세요.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(6)
            }
        } else {
            GroupBox(label: Text("저장 위치").font(.subheadline)) {
                Text(viewModel.memoFilePath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
        }
    }

    @ViewBuilder
    private var editorSection: some View {
        GroupBox(label: Text("메모 내용").font(.subheadline)) {
            autoGrowingEditor
                .padding(6)
        }
    }

    @ViewBuilder
    private var autoGrowingEditor: some View {
        ZStack(alignment: .topLeading) {
            // 텍스트 높이를 드라이브하는 숨겨진 복본
            Text(viewModel.memoText.isEmpty ? " " : viewModel.memoText)
                .font(.system(size: CGFloat(viewModel.fontSize)))
                .opacity(0)
                .padding(.horizontal, 5)
                .padding(.vertical, 9)
            TextEditor(text: $viewModel.memoText)
                .font(.system(size: CGFloat(viewModel.fontSize)))
                .scrollContentBackground(.hidden)
                .background(Color(.textBackgroundColor).opacity(0.4))
        }
        .frame(minHeight: 80)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var settingsSection: some View {
        GroupBox(label: Text("표시 설정").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 12) {
                fontSizeRow
                fontColorRow
                bgAlphaRow
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var fontSizeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("폰트 크기")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.fontSize)pt")
                    .font(.caption)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(viewModel.fontSize) },
                    set: { viewModel.fontSize = Int($0.rounded()) }
                ),
                in: 10...32, step: 1
            )
        }
    }

    @ViewBuilder
    private var fontColorRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("폰트 색상")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(ColorPreset.allCases, id: \.self) { preset in
                    colorButton(preset)
                }
            }
        }
    }

    @ViewBuilder
    private func colorButton(_ preset: ColorPreset) -> some View {
        let (r, g, b) = preset.rgb
        let isSelected = viewModel.fontColor == preset
        Button {
            viewModel.fontColor = preset
        } label: {
            Text(preset.displayLabel)
                .font(.caption.bold())
                .foregroundStyle(Color(red: r, green: g, blue: b))
                .frame(width: 36, height: 24)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var bgAlphaRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("배경 투명도")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.bgAlpha)%")
                    .font(.caption)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(viewModel.bgAlpha) },
                    set: { viewModel.bgAlpha = Int($0.rounded()) }
                ),
                in: 0...100, step: 1
            )
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button("저장") { viewModel.save() }
                .disabled(viewModel.wowAddonsPath.isEmpty)

            if let result = viewModel.lastSaveResult {
                Text(result)
                    .font(.caption2)
                    .foregroundStyle(result.contains("실패") ? Color.red : Color.green)
            } else if !viewModel.isSaved {
                Text("● 미저장")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - ColorPreset display helpers

private extension ColorPreset {
    var displayLabel: String {
        switch self {
        case .white:  return "흰"
        case .yellow: return "노"
        case .orange: return "주"
        case .red:    return "빨"
        case .cyan:   return "청"
        case .green:  return "초"
        }
    }
}
