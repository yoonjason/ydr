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
            // 인덱스 범위 자동 clamp 바인딩 — bossList 크기 변경 시 stale index 로 인한 out-of-range 방어.
            let safeBinding = Binding<Int>(
                get: {
                    let i = viewModel.selectedBossIndex
                    if viewModel.bossList.isEmpty { return 0 }
                    return min(max(i, 0), viewModel.bossList.count - 1)
                },
                set: { viewModel.selectedBossIndex = $0 }
            )
            Picker("", selection: safeBinding) {
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
                    // id 기반 ForEach (UUID) — 삭제/이동 시 바인딩 안정성 확보.
                    ForEach(viewModel.editableLines) { line in
                        lineRow(for: line.id)
                    }
                }
                Button("라인 추가") { viewModel.addLine() }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
            .padding(6)
        }
    }

    // 라인 id 로 찾아 값·콜백 분리 전달. 배열 인덱스 의존 없음 → 이동·삭제 race 방어.
    @ViewBuilder
    private func lineRow(for id: UUID) -> some View {
        if let line = viewModel.editableLines.first(where: { $0.id == id }) {
            HStack(spacing: 6) {
                Picker("", selection: Binding(
                    get: { line.priority },
                    set: { viewModel.updateLine(id: id, priority: $0) }
                )) {
                    Text("필수").tag(TacticalPriority.critical)
                    Text("권장").tag(TacticalPriority.important)
                    Text("노트").tag(TacticalPriority.note)
                }
                .labelsHidden()
                .frame(width: 90)

                TextField("스킬명 (비우면 보스 전체 주의사항)", text: Binding(
                    get: { line.abilityName },
                    set: { viewModel.updateLine(id: id, abilityName: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

                TextField("행동", text: Binding(
                    get: { line.action },
                    set: { viewModel.updateLine(id: id, action: $0) }
                ))
                .textFieldStyle(.roundedBorder)

                Button { viewModel.moveLineUp(id: id) } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)

                Button { viewModel.moveLineDown(id: id) } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)

                Button(role: .destructive) {
                    viewModel.deleteLine(id: id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
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
            Button {
                viewModel.exportToFile()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            Button {
                viewModel.importFromFile()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
        }
    }
}
