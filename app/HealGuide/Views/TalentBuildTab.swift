import SwiftUI

struct TalentBuildTab: View {
    @ObservedObject var viewModel: TalentBuildViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                credentialsSection
                Divider()
                inputSection
                Divider()
                actionSection
                stateSection
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 600)
        .onAppear { viewModel.onAppear() }
    }

    // MARK: - Credentials

    @ViewBuilder
    private var credentialsSection: some View {
        GroupBox(label: Text("WarcraftLogs API 자격증명").font(.headline)) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Client ID", text: $viewModel.clientID)
                    .textFieldStyle(.roundedBorder)
                SecureField("Client Secret", text: $viewModel.clientSecret)
                    .textFieldStyle(.roundedBorder)
                Text("로그 분석 탭과 자격증명을 공유합니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    // MARK: - Input

    @ViewBuilder
    private var inputSection: some View {
        GroupBox(label: Text("조회 조건").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("던전").frame(width: 80, alignment: .leading)
                    Picker("", selection: $viewModel.selectedDungeon) {
                        Text("선택...").tag(Optional<DungeonInfo>.none)
                        ForEach(viewModel.availableDungeons) { dungeon in
                            Text(dungeon.name).tag(Optional(dungeon))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                HStack {
                    Text("난이도").frame(width: 80, alignment: .leading)
                    Picker("", selection: $viewModel.selectedDifficulty) {
                        ForEach(RankerDifficulty.allCases) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                    .onChange(of: viewModel.selectedDifficulty) { _, _ in
                        viewModel.resetDungeonSelectionIfNeeded()
                    }
                }

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
                    Text("상위 N").frame(width: 80, alignment: .leading)
                    Picker("", selection: $viewModel.topNCount) {
                        ForEach(TopNCount.allCases) { count in
                            Text(count.displayName).tag(count)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Action

    @ViewBuilder
    private var actionSection: some View {
        HStack {
            Button("빌드 조회") { viewModel.startCollect() }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || viewModel.selectedDungeon == nil)

            if isBusy {
                Button("중지") { viewModel.cancelCollect() }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
            }

            if case .success = viewModel.state {
                Button("초기화") { viewModel.reset() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - State

    @ViewBuilder
    private var stateSection: some View {
        switch viewModel.state {
        case .idle:
            Text("조건을 설정하고 '빌드 조회'를 눌러주세요. 상위 N명의 탤런트 export 문자열을 수집해 빈도순으로 보여드립니다.")
                .foregroundStyle(.secondary)

        case .collecting(let completed, let total, let name):
            collectingView(completed: completed, total: total, name: name)

        case .success(let result):
            resultView(result: result)

        case .failure(let message):
            Text(message).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func collectingView(completed: Int, total: Int, name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView().scaleEffect(0.8)
                Text(name).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(completed), total: Double(max(total, 1)))
            Text("\(completed) / \(total) 처리됨")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func resultView(result: TalentBuildCollectionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryBox(result: result)
            ForEach(Array(result.groups.enumerated()), id: \.element.id) { index, group in
                buildCard(rank: index + 1, group: group, totalSamples: result.totalSamples)
            }
            if let feedback = viewModel.lastCopyFeedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func summaryBox(result: TalentBuildCollectionResult) -> some View {
        GroupBox(label: Text("수집 요약").font(.headline)) {
            VStack(alignment: .leading, spacing: 4) {
                metaRow("던전",       result.dungeonName)
                metaRow("난이도",     result.difficulty.rawValue)
                metaRow("스펙",       result.spec.displayName)
                metaRow("샘플 수",    "\(result.totalSamples) / \(result.requestedRankers)명 (import 문자열 획득)")
                metaRow("빌드 종류",  "\(result.groups.count)개")
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func buildCard(rank: Int, group: TalentBuildGroup, totalSamples: Int) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("#\(rank) 빌드")
                        .font(.headline)
                    Text("\(group.usageCount) / \(totalSamples)명 사용 (\(Int(group.usageRatio * 100))%)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        viewModel.copyImportCode(group.importCode, rank: rank)
                    } label: {
                        Label("복사", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                }

                // 사용 랭커 목록 — 각 이름을 해당 WCL 리포트 링크로 렌더 (클릭 시 브라우저 열림)
                VStack(alignment: .leading, spacing: 2) {
                    Text("사용 랭커 (\(group.samples.count)명):")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    FlowText(samples: group.samples)
                }

                ImportCodeView(code: group.importCode)
            }
            .padding(8)
        }
    }

    // 복사 버튼이 주 수단이지만 사용자가 전체 코드를 확인하고 싶을 수 있어
    // 접힘/펼침 토글과 전체 선택 가능한 selectable 상태를 동시 제공.
    private struct ImportCodeView: View {
        let code: String
        @State private var expanded: Bool = false

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(code)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                    .lineLimit(expanded ? nil : 1)
                    .truncationMode(.tail)

                Button(expanded ? "접기" : "전체 보기") {
                    expanded.toggle()
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
    }

    // 랭커 이름을 WCL 리포트 링크로 나열. Wrap 처리를 위해 내부에 Text 연결.
    private struct FlowText: View {
        let samples: [TalentImportSample]

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(samples) { sample in
                    HStack(spacing: 4) {
                        if let url = sample.warcraftLogsURL {
                            Link(destination: url) {
                                HStack(spacing: 3) {
                                    Text(sample.characterName)
                                        .font(.caption2)
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.blue)
                            }
                            Text("(\(sample.reportCode)#fight=\(sample.fightID))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(sample.characterName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value).font(.caption)
        }
    }

    private var isBusy: Bool {
        if case .collecting = viewModel.state { return true }
        return false
    }
}
