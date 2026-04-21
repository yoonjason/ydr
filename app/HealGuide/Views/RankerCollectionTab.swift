import SwiftUI

struct RankerCollectionTab: View {
    @ObservedObject var viewModel: RankerCollectionViewModel
    @StateObject private var scheduler = AutoCollectScheduler()

    // 경로 미설정 시 자동 펼침. 사용자가 수동으로 접었다 펼 수도 있도록 @State 유지.
    @State private var isWowPathExpanded: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                credentialsSection
                wowPathSection
                Divider()
                inputSection
                Divider()
                actionSection
                autoCollectSection
                stateSection
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 600)
        .onAppear {
            viewModel.onAppear()
            isWowPathExpanded = viewModel.wowAddonsPath.isEmpty
            // 스케줄러 발사 시 자동으로 수집 시작
            scheduler.onFire = { [weak viewModel] in
                viewModel?.startCollect()
            }
        }
    }

    // MARK: - WoW AddOns 경로

    @ViewBuilder
    private var wowPathSection: some View {
        DisclosureGroup(isExpanded: $isWowPathExpanded) {
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
        } label: {
            HStack(spacing: 6) {
                Text("WoW AddOns 경로 (HGPT_RankerData.lua 저장)")
                if viewModel.wowAddonsPath.isEmpty {
                    Text("필수")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.25))
                        .foregroundStyle(.orange)
                        .cornerRadius(4)
                }
            }
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
            Button("지금 수집") { viewModel.startCollect() }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || viewModel.selectedDungeon == nil)

            if isBusy {
                Button("중지") { viewModel.cancelCollect() }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
            }

            if !isIdle {
                Button("초기화") { viewModel.reset() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 자동 수집 (베타)

    @ViewBuilder
    private var autoCollectSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text("앱 실행 중에만 동작합니다. 지정 시간에 알림 + 마지막 선택한 던전/스펙으로 자동 수집.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("빈도").frame(width: 60, alignment: .leading)
                    Picker("", selection: $scheduler.frequency) {
                        ForEach(AutoCollectScheduler.Frequency.allCases) { f in
                            Text(f.displayName).tag(f)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
                if scheduler.frequency != .off {
                    HStack {
                        Text("시간").frame(width: 60, alignment: .leading)
                        Picker("", selection: $scheduler.hourOfDay) {
                            ForEach(0..<24, id: \.self) { h in
                                Text("\(String(format: "%02d", h))시").tag(h)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 100)
                    }
                    if scheduler.frequency == .weekly {
                        HStack {
                            Text("요일").frame(width: 60, alignment: .leading)
                            Picker("", selection: $scheduler.weekday) {
                                Text("일").tag(0)
                                Text("월").tag(1)
                                Text("화").tag(2)
                                Text("수").tag(3)
                                Text("목").tag(4)
                                Text("금").tag(5)
                                Text("토").tag(6)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 240)
                        }
                    }
                    if let next = scheduler.nextFireDate {
                        Text("다음 예정: \(next.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    Button("지금 바로 발사 (테스트)") { scheduler.fireNow() }
                        .buttonStyle(.bordered)
                        .font(.caption2)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Text("자동 수집 (베타)")
                if scheduler.frequency != .off {
                    Text(scheduler.frequency.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.25))
                        .foregroundStyle(.green)
                        .cornerRadius(4)
                }
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
                        viewModel.startCollect()
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
            GroupBox(label: HStack {
                Text("수집 결과").font(.headline)
                if viewModel.hasUnsavedPreview {
                    Text("미저장")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .cornerRadius(4)
                }
                Spacer()
                Button("저장") { viewModel.saveLua() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSaveToFile)
                if !viewModel.canSaveToFile {
                    Text("AddOns 경로 미설정")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }) {
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

            // 보스 스킬 매핑 목록 — 접이식: 행 클릭 시 힐 스킬 상세 + 기믹 설명 펼침
            if !preview.bossEntries.isEmpty {
                GroupBox(label: Text("보스별 매핑 (행 클릭 시 상세)").font(.subheadline)) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(preview.bossEntries, id: \.compositeID) { entry in
                                BossMappingRow(entry: entry, data: data)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 400)
                }
            }

            // 메타데이터 패널
            metadataPanel(meta: data.meta)

            if let saveResult = viewModel.lastSaveResult {
                Text(saveResult)
                    .font(.caption2)
                    .foregroundStyle(saveResult.contains("완료") ? .green : .red)
            }

            // 필터 완화 버튼
            if preview.parsesFiltered < max(1, preview.parsesCollected / 2) {
                Button("필터 완화 (유사도 → 0.6) 후 재수집") {
                    viewModel.relaxFilter()
                    viewModel.startCollect()
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

// MARK: - BossMappingRow

// 보스별 매핑 행. 클릭하면 힐 스킬 + 기믹 설명 상세 펼침.
// entry: 순위/카운트 메타, data: 힐 상세·한국어 스킬명·기믹 설명 조회용.
private struct BossMappingRow: View {
    let entry: RankerPreviewResult.BossEntry
    let data: HGPTRankerData
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            if expanded {
                expandedDetail
                    .padding(.leading, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
            }
        }
        .padding(6)
        .background(expanded ? Color.secondary.opacity(0.08) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
        }
    }

    private var headerRow: some View {
        HStack {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(entry.encounterName ?? "Enc \(entry.encounterID)")
                .font(.caption)
                .frame(width: 140, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(entry.bossSpellName ?? "Boss #\(entry.bossSpellID)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 200, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text("힐 스킬 \(entry.mappingCount)개")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var expandedDetail: some View {
        // 0. 사용자 큐레이션 전술 가이드 (있으면 최상단에 우선 표시)
        if let tactics = data.tacticalLines[entry.encounterID]?[entry.bossSpellID], !tactics.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Label("전술 가이드", systemImage: "scope")
                    .font(.caption2)
                    .foregroundStyle(.pink)
                ForEach(Array(tactics.enumerated()), id: \.offset) { _, t in
                    HStack(alignment: .top, spacing: 4) {
                        Text(t.priorityMarker)
                            .font(.caption2)
                            .foregroundStyle(t.priority == .critical ? .red : .orange)
                        Text(t.action)
                            .font(.caption2)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.bottom, 4)
        }

        // 1. 기믹 설명 (Blizzard API)
        if let desc = data.abilityDescriptions[entry.encounterID]?[entry.bossSpellID], !desc.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Label("기믹 설명", systemImage: "book")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // 1b. 범용 힐러 가이드 (키워드 파싱) — 매칭 없으면 섹션 자체 생략
                let hints = HealerHintGenerator.generate(from: desc)
                if !hints.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(hints, id: \.self) { hint in
                            Text(hint)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.bottom, 4)
        }

        // 2. 힐 스킬 리스트 (랭커 데이터)
        // BLOCKER-2: 동일 boss 스킬에 같은 healer spellID 가 다른 delay 로 복수 등장 가능 →
        // spellID 단독 id 는 충돌. enumerated().offset 으로 순서 기반 고유 id 사용.
        if let healerEntries = data.encounterData[entry.encounterID]?[entry.bossSpellID],
           !healerEntries.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Label("힐 스킬 (랭커 데이터)", systemImage: "cross.circle")
                    .font(.caption2)
                    .foregroundStyle(.green)
                ForEach(Array(healerEntries.enumerated()), id: \.offset) { _, he in
                    healerRow(he)
                }
            }
        }
    }

    private func healerRow(_ he: RankerResponseEntry) -> some View {
        let spellName = data.spellNames[he.spellID] ?? "Spell #\(he.spellID)"
        let delayText = String(format: "%.1f초 후", he.delay)
        let quorumText = "\(he.quorum)명 사용"
        let stddevText = he.stddev >= 2.0 ? " • ⚠ 편차 \(String(format: "%.1f", he.stddev))초" : ""
        return HStack(spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(spellName)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 180, alignment: .leading)
            Text(delayText)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("(\(quorumText)\(stddevText))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }
}
