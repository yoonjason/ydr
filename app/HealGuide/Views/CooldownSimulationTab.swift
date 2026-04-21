import SwiftUI

// 베타 — 쿨타임 fallback 시뮬레이션.
// 수집된 랭커 데이터 기반으로 "현재 내 쿨타임 상태" 를 가정해 어떤 힐 스킬이
// 추천되는지 미리 확인. 실제 인게임 없이 애드온 동작 시뮬레이션.
struct CooldownSimulationTab: View {
    @StateObject private var viewModel = CooldownSimulationViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerNotice
                inputSection
                Divider()
                if viewModel.hasData {
                    cooldownCheckSection
                    Divider()
                    resultsSection
                } else {
                    emptyState
                }
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 700)
        .onAppear { viewModel.onAppear() }
    }

    // MARK: - Notice

    @ViewBuilder
    private var headerNotice: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Label("베타 기능 — 시뮬레이션", systemImage: "flask")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("랭커 수집 탭에서 미리 수집한 데이터를 기반으로 '내 쿨타임 상태' 를 가정해 어떤 힐 스킬이 추천되는지 미리 확인합니다. 실제 인게임과 다를 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("카테고리 태깅 범위: 수양 사제 / 신성 사제. 나머지 스펙은 태깅 스킬 없음.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(6)
        }
    }

    // MARK: - Input

    @ViewBuilder
    private var inputSection: some View {
        GroupBox(label: Text("시뮬레이션 설정").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("스펙").frame(width: 80, alignment: .leading)
                    Picker("", selection: $viewModel.selectedSpec) {
                        ForEach(HealerSpec.allCases) { spec in
                            Text(spec.displayName).tag(spec)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                HStack {
                    Text("던전").frame(width: 80, alignment: .leading)
                    Picker("", selection: $viewModel.selectedDungeon) {
                        Text("선택...").tag(Optional<DungeonInfo>.none)
                        ForEach(DungeonInfo.currentSeason) { dungeon in
                            Text(dungeon.name).tag(Optional(dungeon))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(6)
        }
    }

    // MARK: - Cooldown checkboxes

    @ViewBuilder
    private var cooldownCheckSection: some View {
        GroupBox(label: HStack {
            Text("내 쿨타임 상태").font(.subheadline)
            Spacer()
            Button("모두 쿨") { viewModel.setAllOnCooldown() }
                .font(.caption2)
                .buttonStyle(.bordered)
            Button("초기화") { viewModel.clearCooldowns() }
                .font(.caption2)
                .buttonStyle(.bordered)
        }) {
            if viewModel.availableSpells.isEmpty {
                Text("이 스펙은 카테고리 태깅된 스킬이 없습니다. (수양 사제 / 신성 사제만 지원)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], alignment: .leading, spacing: 4) {
                    ForEach(viewModel.availableSpells) { row in
                        cooldownRow(row)
                    }
                }
                .padding(6)
            }
        }
    }

    @ViewBuilder
    private func cooldownRow(_ row: HealerSpellRow) -> some View {
        let onCD = viewModel.cooldownSpellIDs.contains(row.spellID)
        HStack {
            Toggle(isOn: Binding(
                get: { onCD },
                set: { _ in viewModel.toggleCooldown(spellID: row.spellID) }
            )) {
                HStack(spacing: 4) {
                    Text("[\(row.category.displayName)]")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(row.name)
                        .font(.caption)
                        .strikethrough(onCD)
                }
            }
            .toggleStyle(.checkbox)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        GroupBox(label: Text("시뮬레이션 결과 — \(viewModel.results.count)개 보스 스킬").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.results) { result in
                    simulationRow(result)
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private func simulationRow(_ result: SimulationResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(result.encounterName)
                    .font(.caption)
                    .frame(width: 140, alignment: .leading)
                    .lineLimit(1)
                Text(result.bossSpellName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 200, alignment: .leading)
                    .lineLimit(1)
            }
            // 추천 스킬
            if let rec = result.recommended {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption2)
                    Text("추천:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let cat = rec.category {
                        Text("[\(cat.displayName)]")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text(rec.spellName)
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("(\(String(format: "%.1fs", rec.delay)), \(rec.quorum))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 14)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption2)
                    Text("모두 쿨 또는 데이터 없음")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                .padding(.leading, 14)
            }
            // 대안/스킵 (쿨타임 체크된 것)
            // BLOCKER-1 대응: spellID 단독 id 는 같은 skipped 배열 내 중복 가능 → enumerated().offset 사용
            if !result.skipped.isEmpty {
                ForEach(Array(result.skipped.enumerated()), id: \.offset) { _, sk in
                    HStack(spacing: 4) {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.gray)
                            .font(.caption2)
                        Text("대안/스킵:")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if let cat = sk.category {
                            Text("[\(cat.displayName)]")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(sk.spellName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .strikethrough(viewModel.cooldownSpellIDs.contains(sk.spellID))
                        Text("(\(sk.quorum))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.leading, 28)
                }
            }
        }
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(4)
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("수집된 랭커 데이터 없음")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("이 스펙·던전 조합으로 수집된 랭커 데이터가 캐시에 없습니다. '랭커 수집' 탭에서 먼저 수집 후 저장해주세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
