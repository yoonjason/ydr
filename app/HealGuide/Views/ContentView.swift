//
//  ContentView.swift
//  HealGuide
//
//  최소 플레이스홀더. 실제 UI는 Claude Code 가 PROJECT_PLAN.md Phase 1 단계에서 구현.
//

import SwiftUI

struct ContentView: View {

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.heart")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("HealGuide")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("WoW 힐러 가이드 생성기")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Phase 1 구현 대기 중 — PROJECT_PLAN.md 참조")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
