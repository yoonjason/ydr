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
        .sheet(isPresented: $viewModel.showNewSpellSheet) {
            NewSpellApprovalSheet(viewModel: viewModel)
        }
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
        blizzardCredentialsSection
        wowPathSection
    }

    @ViewBuilder
    private var wowPathSection: some View {
        DisclosureGroup("WoW AddOns 경로 (파일 직접 저장)") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Lua 파일을 직접 저장하려면 WoW AddOns 폴더 경로를 지정하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("/Applications/World of Warcraft/_retail_/Interface/AddOns", text: $viewModel.wowAddonsPath)
                        .textFieldStyle(.roundedBorder)
                    Button("선택") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.message = "WoW Interface/AddOns 폴더를 선택하세요"
                        if panel.runModal() == .OK, let url = panel.url {
                            viewModel.wowAddonsPath = url.path
                        }
                    }
                }
                if let result = viewModel.lastSaveResult {
                    Text(result)
                        .font(.caption2)
                        .foregroundStyle(result.hasPrefix("저장 완료") ? .green : .red)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var blizzardCredentialsSection: some View {
        DisclosureGroup("Blizzard API (선택사항)") {
            VStack(alignment: .leading, spacing: 6) {
                Text("developer.battle.net 에서 발급받은 자격증명. 신규 스킬의 한국어 이름 자동 해상에 사용됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Blizzard Client ID", text: $viewModel.blizzardClientID)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    if viewModel.isBlizzardSecretVisible {
                        TextField("Blizzard Client Secret", text: $viewModel.blizzardClientSecret)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Blizzard Client Secret", text: $viewModel.blizzardClientSecret)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        viewModel.isBlizzardSecretVisible.toggle()
                    } label: {
                        Image(systemName: viewModel.isBlizzardSecretVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if viewModel.hasBlizzardCredentials {
                    Text("설정됨 — 신규 스킬 승인 시 Blizzard API 로 한국어 이름을 가져옵니다.")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            .padding(.top, 4)
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
        let catalog = viewModel.resolvedSpells(for: spec)

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
                                    if let iconURL = entry.iconURL, let url = URL(string: iconURL) {
                                        AsyncImage(url: url) { image in
                                            image.resizable()
                                        } placeholder: {
                                            Color.gray.opacity(0.3)
                                        }
                                        .frame(width: 20, height: 20)
                                        .cornerRadius(4)
                                    }
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
                if viewModel.canSaveToFile {
                    Button("파일로 저장") { viewModel.saveToFile() }
                        .buttonStyle(.bordered)
                }
            }

            if !output.bossNameMap.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(output.blocks, id: \.encounterID) { block in
                            let krName = output.bossNameMap[block.encounterID]
                            HStack(spacing: 4) {
                                Text(krName ?? block.name)
                                    .font(.caption)
                                if krName != nil {
                                    Text("(\(block.name))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
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
                        if !viewModel.discoveredSpells.isEmpty {
                            Button("카탈로그에 추가...") { viewModel.showNewSpellSheet = true }
                                .font(.caption)
                        }
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
        pasteboard: MockPasteboard(),
        spellResolver: SpellResolver(store: SpellCatalogStore())
    ))
}
