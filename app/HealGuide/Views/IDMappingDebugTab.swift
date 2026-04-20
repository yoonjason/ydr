import SwiftUI
import os

// encounterID/dungeonID 매핑 조사용 디버그 탭.
// 현재 RankerNameResolver 가 WCL encID 를 Blizzard journal-encounter 에 그대로 넘겨
// 잘못된 레이드 보스 이름을 반환하는 버그가 있음. 올바른 엔드포인트를 찾기 위한 실험실.
struct IDMappingDebugTab: View {
    @StateObject private var viewModel = IDMappingDebugViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("ID 매핑 조사용 디버그 도구")
                    .font(.headline)
                Text("WCL encID 를 여러 엔드포인트에 넣어 실제 응답을 확인하고 올바른 이름 조회 경로를 찾는다. 버튼별로 결과가 하단 텍스트 영역에 누적된다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                credentialsSection
                Divider()
                inputSection
                Divider()
                actionButtons
                Divider()
                resultSection
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 700)
        .onAppear { viewModel.onAppear() }
    }

    @ViewBuilder
    private var credentialsSection: some View {
        GroupBox(label: Text("자격증명 (기존 저장소 공유)").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("WCL Client ID").font(.caption).frame(width: 160, alignment: .leading)
                    TextField("", text: $viewModel.wclClientID).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("WCL Client Secret").font(.caption).frame(width: 160, alignment: .leading)
                    SecureField("", text: $viewModel.wclClientSecret).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Blizzard Client ID").font(.caption).frame(width: 160, alignment: .leading)
                    TextField("", text: $viewModel.blizzardClientID).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Blizzard Client Secret").font(.caption).frame(width: 160, alignment: .leading)
                    SecureField("", text: $viewModel.blizzardClientSecret).textFieldStyle(.roundedBorder)
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var inputSection: some View {
        GroupBox(label: Text("조회 ID").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("WCL encID").font(.caption).frame(width: 160, alignment: .leading)
                    TextField("예: 12805 (Windrunner Spire)", text: $viewModel.wclEncounterID)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("CM mapID (M+)").font(.caption).frame(width: 160, alignment: .leading)
                    TextField("예: 2805 (WCL encID 에서 앞 자리 제거 시도)", text: $viewModel.cmMapID)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Blizzard journalEncounterID").font(.caption).frame(width: 160, alignment: .leading)
                    TextField("예: 2562 (_name 에 엉뚱한 이름이 박힌 ID)", text: $viewModel.journalEncounterID)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Blizzard journalInstanceID").font(.caption).frame(width: 160, alignment: .leading)
                    TextField("예: 1273 (Nerub'ar Palace)", text: $viewModel.journalInstanceID)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("엔드포인트별 조회").font(.subheadline)

            HStack {
                Button("WCL worldData.encounter(id:).name") {
                    Task { await viewModel.queryWCLEncounterName() }
                }
                .buttonStyle(.borderedProminent)
                Text("옵션 C — WCL 자체 name (가장 안전할 것으로 예상)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Button("Blizzard journal-encounter/{encID}") {
                    Task { await viewModel.queryBlizzardJournalEncounter() }
                }
                .buttonStyle(.bordered)
                Text("현재 버그 방식 (비교 기준)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Button("Blizzard journal-encounter/{journalEncounterID}") {
                    Task { await viewModel.queryBlizzardJournalEncounterForJournalID() }
                }
                .buttonStyle(.bordered)
                Text("journalEncounterID 로 조회 — 레이드 보스 확인용")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Button("Blizzard journal-instance/{journalInstanceID}") {
                    Task { await viewModel.queryBlizzardJournalInstance() }
                }
                .buttonStyle(.bordered)
                Text("인스턴스 단위 — encounters[] 배열로 보스 리스트")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Button("Blizzard mythic-keystone/dungeon/index") {
                    Task { await viewModel.queryBlizzardMPlusIndex() }
                }
                .buttonStyle(.bordered)
                Text("M+ 전용 — 전체 던전 목록 (dungeonID=CM mapID)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Button("Blizzard mythic-keystone/dungeon/{cmMapID}") {
                    Task { await viewModel.queryBlizzardMPlusDungeon() }
                }
                .buttonStyle(.bordered)
                Text("M+ 던전 상세 — encounters 필드 존재 여부 확인")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Button("결과 지우기") { viewModel.clearResults() }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("결과 (최신이 위)").font(.subheadline)
            if viewModel.isBusy {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text(viewModel.currentAction).font(.caption).foregroundStyle(.secondary)
                }
            }
            TextEditor(text: .constant(viewModel.resultLog))
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 300)
                .border(Color.secondary.opacity(0.3))
        }
    }
}
