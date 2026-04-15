import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ReportViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                inputsSection
                Divider()
                stateSection
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 600)
        .onAppear { viewModel.onAppear() }
    }

    // MARK: - 입력

    @ViewBuilder
    private var inputsSection: some View {
        GroupBox(label: Text("리포트").font(.headline)) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("WarcraftLogs Report URL", text: $viewModel.reportURLText)
                    .textFieldStyle(.roundedBorder)
                TextField("Client ID", text: $viewModel.clientID)
                    .textFieldStyle(.roundedBorder)
                secretField
                HStack {
                    Button("힐러 감지") {
                        Task { await viewModel.detectHealers() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)

                    if viewModel.state != .idle {
                        Button("초기화") {
                            viewModel.resetToIdle()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(8)
        }
    }

    private var isBusy: Bool {
        switch viewModel.state {
        case .detectingHealers, .generating: return true
        default: return false
        }
    }

    @ViewBuilder
    private var secretField: some View {
        HStack {
            if viewModel.isSecretVisible {
                TextField("Client Secret", text: $viewModel.clientSecret)
                    .textFieldStyle(.roundedBorder)
            } else {
                SecureField("Client Secret", text: $viewModel.clientSecret)
                    .textFieldStyle(.roundedBorder)
            }
            Button {
                viewModel.isSecretVisible.toggle()
            } label: {
                Image(systemName: viewModel.isSecretVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 상태별 뷰

    @ViewBuilder
    private var stateSection: some View {
        switch viewModel.state {
        case .idle:
            Text("URL 과 크레덴셜을 입력하고 '힐러 감지' 를 눌러주세요.")
                .foregroundStyle(.secondary)
        case .detectingHealers:
            ProgressView("힐러 정보 불러오는 중...")
        case .healerSelection(let healers, let dungeonName):
            healerSelectionView(healers: healers, dungeonName: dungeonName)
        case .spellSelection(let healer):
            spellSelectionView(healer: healer)
        case .generating:
            ProgressView("Lua 생성 중...")
        case .success(let output, let unknown):
            successView(output: output, unknown: unknown)
        case .failure(let error):
            Text(error.errorDescription ?? "알 수 없는 오류가 발생했습니다.")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func healerSelectionView(healers: [HealerCandidate], dungeonName: String) -> some View {
        GroupBox(label: Text("힐러 선택 — \(dungeonName)").font(.headline)) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("힐러", selection: Binding(
                    get: { viewModel.selectedHealerID ?? (healers.first?.id ?? 0) },
                    set: { viewModel.selectedHealerID = $0 }
                )) {
                    ForEach(healers) { healer in
                        Text(healer.displayName).tag(healer.id)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Button("다음 → 주문 선택") { viewModel.confirmHealerSelection() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func spellSelectionView(healer: HealerCandidate) -> some View {
        let spec = healer.healerSpec ?? .discPriest
        let catalog = SpecSpellCatalog.spells(for: spec)

        GroupBox(label: Text("주문 선택 — \(healer.name) (\(spec.displayName))").font(.headline)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("전체 선택") { viewModel.checkAllSpells() }
                    Button("전체 해제") { viewModel.uncheckAllSpells() }
                    Spacer()
                    Text("\(viewModel.selectedSpellIDs.count) / \(catalog.count) 선택")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(catalog) { entry in
                            Toggle(isOn: Binding(
                                get: { viewModel.selectedSpellIDs.contains(entry.id) },
                                set: { _ in viewModel.toggleSpell(entry.id) }
                            )) {
                                HStack {
                                    Text(entry.nameKR)
                                    Text("(\(entry.nameEN))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("#\(entry.id)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 200, maxHeight: 360)

                HStack {
                    Button("← 뒤로") { viewModel.backToHealerSelection() }
                    Spacer()
                    Button("Lua 생성") { Task { await viewModel.generate() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.selectedSpellIDs.isEmpty)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func successView(output: LuaOutput, unknown: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Lua 생성 완료 (보스 \(output.blockCount) / 타임라인 \(output.timelineCount) / 반응 \(output.reactionCount))")
                    .font(.headline)
                Spacer()
                Button("클립보드에 복사") { viewModel.copyToClipboard() }
                    .buttonStyle(.borderedProminent)
            }

            if !unknown.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("카탈로그에 없는 주문 \(unknown.count)개 감지")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                        Text("SpellID: \(unknown.map(String.init).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("가이드에 포함하려면 SpecSpellCatalog.swift 에 추가 후 다시 감지해 주세요.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ScrollView {
                TextEditor(text: .constant(output.luaText))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
            }
            .frame(maxHeight: 300)
        }
    }
}

#Preview("idle") {
    ContentView(viewModel: ReportViewModel(
        urlParser: URLParser(),
        keychain: MockKeychain(),
        apiClient: MockWarcraftLogsAPIClient(),
        normalizer: TimelineNormalizer(),
        luaGenerator: LuaGenerator(),
        pasteboard: MockPasteboard()
    ))
}
