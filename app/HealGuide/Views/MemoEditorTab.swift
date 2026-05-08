import SwiftUI

struct MemoEditorTab: View {
    @StateObject private var viewModel = MemoEditorViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                pathSection
                characterPickerSection
                if viewModel.isCurrentSectionEmpty {
                    emptyCharacterSection
                }
                editorSection
                settingsSection
                Divider()
                actionRow
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 480)
        .onAppear { viewModel.onAppear() }
        .alert("저장하지 않은 변경 사항", isPresented: $viewModel.showDirtyConfirmation) {
            Button("저장 후 전환") { Task { await viewModel.confirmSwitchWithSaving() } }
            Button("저장하지 않고 전환", role: .destructive) { viewModel.confirmSwitchWithoutSaving() }
            Button("취소", role: .cancel) { viewModel.cancelSwitch() }
        } message: {
            Text("현재 섹션에 저장되지 않은 내용이 있습니다.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Label("상시 메모", systemImage: "note.text")
                    .font(.headline)
                Text("공통(shared) 메모는 모든 캐릭터에 적용되며, 캐릭터별 메모는 해당 캐릭터 접속 시 우선 적용됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("저장하면 HGPT_Memo.lua 에 기록됩니다. 인게임 /reload 후 반영.")
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
    private var characterPickerSection: some View {
        GroupBox(label: HStack {
            Text("섹션").font(.subheadline)
            Spacer()
            Button(action: { viewModel.refreshCharacters() }) {
                Label("캐릭터 새로고침", systemImage: "arrow.clockwise")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    sectionButton(key: "shared", label: "공통")

                    if !viewModel.availableCharacters.isEmpty {
                        Divider()
                            .frame(height: 20)
                    }

                    ForEach(viewModel.availableCharacters, id: \.key) { char in
                        sectionButton(key: char.key, label: char.name)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            if let msg = viewModel.lastScanMessage, viewModel.availableCharacters.isEmpty {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private func sectionButton(key: String, label: String) -> some View {
        let isSelected = viewModel.selectedKey == key
        Button {
            viewModel.selectKey(key)
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.bold())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var emptyCharacterSection: some View {
        GroupBox {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("이 캐릭터는 공통 메모를 사용합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("공통에서 복사하여 시작") {
                        viewModel.copyFromShared()
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
                Spacer()
            }
            .padding(6)
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
