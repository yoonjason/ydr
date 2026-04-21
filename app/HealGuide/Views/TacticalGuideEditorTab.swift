import SwiftUI

// 사용자 전술 가이드 편집 탭.
// 하드코딩 default 위에 사용자 override 를 JSON 으로 저장. 재수집 시 자동 반영.
struct TacticalGuideEditorTab: View {
    @StateObject private var viewModel = TacticalGuideEditorViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerNotice
                inputSection
                Divider()
                if !viewModel.bossList.isEmpty {
                    bossSection
                    Divider()
                    linesEditor
                    Divider()
                    actionRow
                    if let msg = viewModel.lastActionResult {
                        Text(msg)
                            .font(.caption2)
                            .foregroundStyle(msg.contains("실패") ? .red : .green)
                    }
                } else {
                    Text("해당 던전에 보스 데이터가 없습니다.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .frame(minWidth: 720, minHeight: 700)
        .onAppear { viewModel.onAppear() }
    }

    // MARK: - Notice

    @ViewBuilder
    private var headerNotice: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Label("전술 가이드 편집기", systemImage: "pencil.and.scribble")
                    .font(.headline)
                    .foregroundStyle(.pink)
                Text("하드코딩 기본값 위에 사용자 편집을 덮어쓰기 합니다. 저장 파일: ~/Library/Application Support/HealGuide/tactical_guide_custom.json")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("편집 후 저장 → 랭커 수집 재실행하면 새 카탈로그로 매칭됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(6)
        }
    }

    // MARK: - Dungeon / Boss picker

    @ViewBuilder
    private var inputSection: some View {
        GroupBox(label: Text("편집 대상").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("던전").frame(width: 60, alignment: .leading)
                    Picker("", selection: $viewModel.selectedDungeon) {
                        ForEach(DungeonInfo.currentSeason) { d in
                            Text(d.name).tag(Optional(d))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var bossSection: some View {
        GroupBox(label: Text("보스 선택").font(.subheadline)) {
            Picker("", selection: $viewModel.selectedBossIndex) {
                ForEach(Array(viewModel.bossList.enumerated()), id: \.offset) { idx, boss in
                    Text("\(boss.koreanBossName) (\(boss.englishBossName))").tag(idx)
                }
            }
            .labelsHidden()
            .padding(6)
        }
    }

    // MARK: - Lines editor

    @ViewBuilder
    private var linesEditor: some View {
        GroupBox(label: Text("전술 라인 편집 (\(viewModel.editableLines.count))").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 4) {
                if viewModel.editableLines.isEmpty {
                    Text("등록된 라인이 없습니다. 아래 '라인 추가' 로 시작하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($viewModel.editableLines) { $line in
                        lineRow($line: $line)
                    }
                }
                Button("라인 추가") { viewModel.addLine() }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private func lineRow(@Binding line: EditableLine) -> some View {
        let l = line
        HStack(spacing: 6) {
            Picker("", selection: $line.priority) {
                Text("★ 필수").tag(TacticalPriority.critical)
                Text("☆ 권장").tag(TacticalPriority.important)
                Text("ℹ 노트").tag(TacticalPriority.note)
            }
            .labelsHidden()
            .frame(width: 100)

            TextField("스킬명 (비우면 보스 전체 주의사항)", text: $line.abilityName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            TextField("행동", text: $line.action)
                .textFieldStyle(.roundedBorder)

            Button { viewModel.moveLineUp(id: l.id) } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)

            Button { viewModel.moveLineDown(id: l.id) } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                viewModel.deleteLine(id: l.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Action row

    @ViewBuilder
    private var actionRow: some View {
        HStack {
            Button("저장") { viewModel.saveCurrent() }
                .buttonStyle(.borderedProminent)
            Button("되돌리기") { viewModel.revertCurrent() }
                .buttonStyle(.bordered)
            Spacer()
        }
    }
}
