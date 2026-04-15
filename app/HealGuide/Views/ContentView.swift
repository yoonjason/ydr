import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ReportViewModel

    var body: some View {
        Form {
            Section("리포트") {
                TextField("WarcraftLogs Report URL", text: $viewModel.reportURLText)
                    .textFieldStyle(.roundedBorder)
                Picker("힐러 스펙", selection: $viewModel.selectedSpec) {
                    ForEach(HealerSpec.allCases) { spec in
                        Text(spec.displayName).tag(spec)
                    }
                }
            }
            Section("인증") {
                TextField("Client ID", text: $viewModel.clientID)
                    .textFieldStyle(.roundedBorder)
                secretField
            }
            Section {
                Button("데이터 가져오기") {
                    Task { await viewModel.fetchFight() }
                }
                .disabled(viewModel.state == .fetching)
            }
            Section("상태") {
                statusView
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 540)
        .onAppear { viewModel.onAppear() }
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

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.state {
        case .idle:
            Text("URL과 크레덴셜을 입력하고 가져오기를 눌러주세요.")
                .foregroundStyle(.secondary)
        case .fetching:
            ProgressView("가져오는 중...")
        case .success(let output):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Lua 생성 완료 (\(output.entryCount)개 항목)")
                        .font(.headline)
                    Spacer()
                    Button("클립보드에 복사") {
                        viewModel.copyToClipboard()
                    }
                    .buttonStyle(.borderedProminent)
                }
                ScrollView {
                    TextEditor(text: .constant(output.luaText))
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                }
                .frame(maxHeight: 300)
            }
        case .failure(let error):
            Text(error.errorDescription ?? "알 수 없는 오류가 발생했습니다.")
                .foregroundStyle(.red)
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
