import SwiftUI

struct RankerCollectionTab: View {
    @ObservedObject var viewModel: RankerCollectionViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                credentialsSection
                wowPathSection
                Divider()
                inputSection
                Divider()
                actionSection
                stateSection
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 600)
        .onAppear { viewModel.onAppear() }
    }

    // MARK: - WoW AddOns 경로

    @ViewBuilder
    private var wowPathSection: some View {
        DisclosureGroup("WoW AddOns 경로 (HGPT_RankerData.lua 저장)") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Lua 파일 저장을 위해 WoW Interface/AddOns 폴더 경로를 지정하세요. 리포트 탭과 공유됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("/Applications/World of Warcraft/_retail_/Interface/AddOns", text: $viewModel.wowAddonsPath)
                        .textFieldStyle(.roundedBorder)
                    Button("선택") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories    = true
                        panel.canChooseFiles          = false
                        panel.allowsMultipleSelection = false
                        panel.message = "WoW Interface/AddOns 폴더를 선택하세요"
                        if panel.runModal() == .OK, let url = panel.url {
                            viewModel.wowAddonsPath = url.path
                        }
                    }
                }
                if !viewModel.wowAddonsPath.isEmpty {
                    Text("설정됨 — \(viewModel.wowAddonsPath)")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - 자격증명

    @ViewBuilder
    private var credentialsSection: some View {
        GroupBox(label: Text("WarcraftLogs API 자격증명").font(.headline)) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Client ID", text: $viewModel.clientID)
                    .textFieldStyle(.roundedBorder)
                SecureField("Client Secret", text: $viewModel.clientSecret)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(8)
        }
    }

    // MARK: - 입력 폼

    @ViewBuilder
    private var inputSection: some View {
        GroupBox(label: Text("수집 조건").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                // 지역
                HStack {
                    Text("지역")
                        .frame(width: 80, alignment: .leading)
                    Text("KR")
                        .foregroundStyle(.secondary)
                    if viewModel.useGlobalFallback {
                        Text("(전세계 확장 활성)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                // 던전
                HStack {
                    Text("던전")
                        .frame(width: 80, alignment: .leading)
                    Picker("", selection: $viewModel.selectedDungeon) {
                        Text("선택...").tag(Optional<DungeonInfo>.none)
                        ForEach(viewModel.availableDungeons) { dungeon in
                            Text(dungeon.name).tag(Optional(dungeon))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                // 난이도
                HStack {
                    Text("난이도")
                        .frame(width: 80, alignment: .leading)
                    Picker("", selection: $viewModel.selectedDifficulty) {
                        ForEach(RankerDifficulty.allCases) { difficulty in
                            Text(difficulty.rawValue).tag(difficulty)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                    .onChange(of: viewModel.selectedDifficulty) { _, _ in
                        viewModel.resetDungeonSelectionIfNeeded()
                    }
                }

                // 스펙
                HStack {
                    Text("스펙")
                        .frame(width: 80, alignment: .leading)
                    Picker("", selection: $viewModel.selectedSpec) {
                        ForEach(HealerSpec.allCases) { spec in
                            Text(spec.displayName).tag(spec)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .onChange(of: viewModel.selectedSpec) { _, _ in
                        viewModel.selectedPreset = nil
                    }
                }

                // 상위 N
                HStack {
                    Text("상위 N")
                        .frame(width: 80, alignment: .leading)
                    Picker("", selection: $viewModel.topNCount) {
                        ForEach(TopNCount.allCases) { count in
                            Text(count.displayName).tag(count)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }

                Divider()

                // 탤런트 필터 — 프리셋 (C)
                HStack(alignment: .top) {
                    Text("탤런트\n프리셋")
                        .frame(width: 80, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("프리셋", selection: $viewModel.selectedPreset) {
                            Text("없음 (필터 해제)").tag(Optional<TalentPreset>.none)
                            ForEach(viewModel.availablePresets) { preset in
                                Text(preset.name).tag(Optional(preset))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 280)
                        Text("스펙 커뮤니티 빌드 기준 필터")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // 탤런트 필터 — 스트링 (A) 고급 토글
                DisclosureGroup(isExpanded: $viewModel.isAdvancedMode) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("게임 내 [탤런트 내보내기] 스트링 붙여넣기", text: $viewModel.talentString)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: viewModel.talentString) { _, _ in
                                    viewModel.validateTalentString()
                                }
                            Picker("유사도", selection: $viewModel.jaccardThreshold) {
                                Text("≥0.8").tag(0.8)
                                Text("≥0.6").tag(0.6)
                                Text("≥0.5").tag(0.5)
                            }
                            .labelsHidden()
                            .frame(width: 70)
                        }
                        if let error = viewModel.talentParseError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if !viewModel.talentString.isEmpty {
                            Text("스트링 파싱 성공 — Jaccard 유사도 ≥\(String(format: "%.1f", viewModel.jaccardThreshold)) 필터 활성")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Text("프리셋 + 스트링 동시 활성화 시 AND 조건")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                } label: {
                    Label("고급: 탤런트 스트링 (방식 A)", systemImage: "slider.horizontal.3")
                        .font(.subheadline)
                }

                // 전세계 확장 옵트인
                Toggle("KR 결과 부족 시 전세계 확장", isOn: $viewModel.useGlobalFallback)
                    .font(.subheadline)
            }
            .padding(8)
        }
    }

    // MARK: - 실행 버튼

    @ViewBuilder
    private var actionSection: some View {
        HStack {
            Button("지금 수집") {
                Task { await viewModel.collect() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || viewModel.selectedDungeon == nil)

            if !isIdle {
                Button("초기화") { viewModel.reset() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 상태별 뷰

    @ViewBuilder
    private var stateSection: some View {
        switch viewModel.state {
        case .idle:
            Text("조건을 설정하고 '지금 수집'을 눌러주세요.")
                .foregroundStyle(.secondary)

        case .collecting(let progress):
            collectingView(progress: progress)

        case .preview(let preview, let data):
            previewView(preview: preview, data: data)

        case .failure(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .foregroundStyle(.red)
                if message.contains("0건") || message.contains("부족") {
                    Button("필터 완화 (유사도 0.8 → 0.6)") {
                        viewModel.relaxFilter()
                        Task { await viewModel.collect() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private func collectingView(progress: RankerCollectionProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text(progress.currentName)
                    .foregroundStyle(.secondary)
            }
            ProgressView(
                value: Double(progress.completed),
                total: Double(max(progress.total, 1))
            )
            Text("\(progress.completed) / \(progress.total) 처리됨")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func previewView(preview: RankerPreviewResult, data: HGPTRankerData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 요약
            GroupBox(label: Text("수집 결과").font(.headline)) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 20) {
                        statItem(label: "수집 파스", value: "\(preview.parsesCollected)명")
                        statItem(label: "필터 통과", value: "\(preview.parsesFiltered)명")
                        statItem(label: "보스 스킬 매핑", value: "\(preview.bossEntries.count)건")
                    }
                    if !preview.highVarianceWarnings.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("⚠ 표준편차 경고 (\(preview.highVarianceWarnings.count)건)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            ForEach(preview.highVarianceWarnings.prefix(3), id: \.self) { warning in
                                Text(warning)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if preview.highVarianceWarnings.count > 3 {
                                Text("…외 \(preview.highVarianceWarnings.count - 3)건")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(6)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding(8)
            }

            // 보스 스킬 매핑 목록
            if !preview.bossEntries.isEmpty {
                GroupBox(label: Text("보스별 매핑").font(.subheadline)) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(preview.bossEntries, id: \.compositeID) { entry in
                                HStack {
                                    Text(entry.encounterName ?? "Enc \(entry.encounterID)")
                                        .font(.caption)
                                        .frame(width: 140, alignment: .leading)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Text(entry.bossSpellName ?? "Boss #\(entry.bossSpellID)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer()
                                    Text("힐 스킬 \(entry.mappingCount)개")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 200)
                }
            }

            // 메타데이터 패널
            metadataPanel(meta: data.meta)

            // 병합 / 저장
            HStack {
                Button("HGPT_RankerData.lua 저장") { viewModel.saveLua() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSaveToFile)
                if !viewModel.canSaveToFile {
                    Text("WoW AddOns 경로 미설정")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let saveResult = viewModel.lastSaveResult {
                Text(saveResult)
                    .font(.caption2)
                    .foregroundStyle(saveResult.contains("완료") ? .green : .red)
            }

            // 필터 완화 버튼
            if preview.parsesFiltered < max(1, preview.parsesCollected / 2) {
                Button("필터 완화 (유사도 → 0.6) 후 재수집") {
                    viewModel.relaxFilter()
                    Task { await viewModel.collect() }
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func metadataPanel(meta: HGPTRankerDataMeta) -> some View {
        GroupBox(label: Text("메타데이터").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 4) {
                metaRow("수집일시", meta.collectedAt)
                metaRow("지역",     meta.region)
                metaRow("던전",     meta.dungeonName)
                metaRow("난이도",   meta.difficulty)
                metaRow("스펙",     meta.spec)
                metaRow("랭커 수",  "\(meta.rankersUsed)/\(meta.rankersRequested)명")
                if !meta.talentFilterPreset.isEmpty {
                    metaRow("탤런트 프리셋", meta.talentFilterPreset)
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var isBusy: Bool {
        if case .collecting = viewModel.state { return true }
        return false
    }

    private var isIdle: Bool {
        if case .idle = viewModel.state { return true }
        return false
    }
}

#Preview {
    RankerCollectionTab(viewModel: RankerCollectionViewModel(
        apiClient:      MockWarcraftLogsAPIClient(),
        rankingService: MockCharacterRankingsService(),
        keychain:       MockKeychain()
    ))
}
