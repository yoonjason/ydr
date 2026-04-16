import SwiftUI

struct NewSpellApprovalSheet: View {
    @ObservedObject var viewModel: ReportViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("새 스킬 \(viewModel.discoveredSpells.count)개 발견")
                .font(.headline)

            Text("카탈로그에 없는 스킬이 로그에서 감지되었습니다. 추가하면 다음 import 시 주문 선택에 포함됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.hasBlizzardCredentials {
                Label("Blizzard API 로 한국어 이름을 가져옵니다.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("Blizzard API 미설정 — WCL 이름으로 저장됩니다.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.discoveredSpells) { spell in
                        Toggle(isOn: Binding(
                            get: { spell.selected },
                            set: { _ in viewModel.toggleDiscoveredSpell(spell.id) }
                        )) {
                            HStack {
                                Text(spell.name)
                                Spacer()
                                Text("#\(spell.id)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 100, maxHeight: 250)

            Divider()

            HStack {
                Button("전체 선택") { viewModel.selectAllDiscoveredSpells() }
                Spacer()
                if viewModel.isResolvingBlizzardNames {
                    ProgressView()
                        .controlSize(.small)
                    Text("이름 해상 중...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("무시") { viewModel.dismissDiscoveredSpells() }
                    .disabled(viewModel.isResolvingBlizzardNames)
                Button("선택 항목 추가") { viewModel.approveDiscoveredSpells() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        viewModel.discoveredSpells.allSatisfy { !$0.selected }
                        || viewModel.isResolvingBlizzardNames
                    )
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 200)
    }
}
