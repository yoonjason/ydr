import SwiftUI
import os

// encounterID/dungeonID 매핑 조사용 디버그 탭.
// 2026-04-21: _name 필드 오염 버그 (WCL encID ↔ Blizzard journal-encounter ID
// 공간 불일치) 근본 원인을 여기서 실기 검증해 WCL worldData.encounter(id:).name
// 경로로 전환했음. 커밋 ee400a3 에서 수정 완료. 이 탭은 추후 유사 매핑 문제
// (신규 시즌/레이드 ID 체계 변경 등) 재발 시 진단 도구로 활용.
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
                .disabled(viewModel.isBusy)
                Text("옵션 C — WCL 자체 name (가장 안전)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Button("Blizzard journal-encounter/{encID}") {
                    Task { await viewModel.queryBlizzardJournalEncounter() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isBusy)
                Text("구 버그 방식 (비교 기준)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Button("Blizzard journal-encounter/{journalEncounterID}") {
                    Task { await viewModel.queryBlizzardJournalEncounterForJournalID() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isBusy)
                Text("journalEncounterID 로 조회 — 레이드 보스 확인용")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Button("Blizzard journal-instance/{journalInstanceID}") {
                    Task { await viewModel.queryBlizzardJournalInstance() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isBusy)
                Text("인스턴스 단위 — encounters[] 배열로 보스 리스트")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Button("Blizzard mythic-keystone/dungeon/index") {
                    Task { await viewModel.queryBlizzardMPlusIndex() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isBusy)
                Text("M+ 전용 — 전체 던전 목록 (dungeonID=CM mapID)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Button("Blizzard mythic-keystone/dungeon/{cmMapID}") {
                    Task { await viewModel.queryBlizzardMPlusDungeon() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isBusy)
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
