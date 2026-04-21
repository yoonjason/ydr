import Foundation
import AppKit
import UserNotifications
import os

// 랭커 데이터 자동 재수집 스케줄러.
// 한계: 앱이 실행 중일 때만 Timer 가 동작. 백그라운드 자동 수집은 macOS
// LaunchAgent 또는 BackgroundTask 필요 (스코프 밖).
// 대신 앱 실행 시 '다음 예정 시각' 을 계산해 Timer 설정 + 도달 시 UNNotification.
//
// 사용자는 알림 받고 앱 열어서 수집 탭에서 수동 실행.
// 자동화: ViewModel 에 '실행 콜백' 주입하면 Timer 발사 시 자동 호출 가능.
@MainActor
final class AutoCollectScheduler: ObservableObject {

    enum Frequency: String, CaseIterable, Codable, Identifiable {
        case off
        case daily
        case weekly

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .off:    return "사용 안 함"
            case .daily:  return "매일"
            case .weekly: return "매주"
            }
        }
    }

    // MARK: - Published

    @Published var frequency: Frequency = .off {
        didSet {
            // ISSUE-3: 권한 요청은 사용자가 실제로 자동 수집을 켤 때만 (off → non-off 전환).
            // 탭 진입만으로 다이얼로그가 뜨는 HIG 위반 방지.
            if oldValue == .off && frequency != .off {
                requestNotificationPermission()
            }
            persist()
            reschedule()
        }
    }
    /// 0~23 시 (한국 시간 기준).
    @Published var hourOfDay: Int = 9 {
        didSet { persist(); reschedule() }
    }
    /// 0 = 일요일, 1 = 월요일, ... 6 = 토요일 (weekly 전용).
    @Published var weekday: Int = 2 {  // 화요일 (주간 리셋 직후)
        didSet { persist(); reschedule() }
    }
    @Published private(set) var nextFireDate: Date?
    @Published private(set) var lastFireMessage: String?

    // MARK: - Dependencies

    private var timer: Timer?
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "AutoCollect")
    private let defaults = UserDefaults.standard
    private let keyFrequency  = "autoCollect.frequency"
    private let keyHour       = "autoCollect.hour"
    private let keyWeekday    = "autoCollect.weekday"

    // 실행 시점에 호출될 콜백. ViewModel 에서 실제 수집 실행 트리거.
    var onFire: (() -> Void)?

    // MARK: - Init

    init() {
        if let raw = defaults.string(forKey: keyFrequency),
           let f = Frequency(rawValue: raw) {
            frequency = f
        }
        hourOfDay = defaults.integer(forKey: keyHour)
        if hourOfDay == 0 && defaults.object(forKey: keyHour) == nil { hourOfDay = 9 }
        weekday = defaults.integer(forKey: keyWeekday)
        if weekday == 0 && defaults.object(forKey: keyWeekday) == nil { weekday = 2 }

        // ISSUE-3: init 에서 권한 요청 제거. frequency 가 off→non-off 로 바뀔 때만 요청.
        reschedule()
    }

    // MARK: - Actions

    /// 지금 즉시 예정 시간을 재계산 + Timer 재등록.
    func reschedule() {
        timer?.invalidate()
        timer = nil
        guard frequency != .off else {
            nextFireDate = nil
            return
        }
        let next = computeNextFireDate()
        nextFireDate = next
        let interval = next.timeIntervalSinceNow
        guard interval > 0 else { return }
        logger.info("다음 자동 수집: \(next, privacy: .public) (in \(Int(interval))s)")

        // Timer 는 최대 ~24일까지는 안정적. 그 이상이면 부정확 가능하지만 weekly 는 최대 7일이라 OK.
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fire()
            }
        }
    }

    /// 수동 테스트 버튼용. reschedule 하지 않음 — 기존 예약 타이머 유지.
    /// 정규 발사(fire)는 예약된 Timer 에서만 일어나고 그 때만 reschedule.
    func fireNow() {
        logger.info("수동 발사 (fireNow)")
        sendNotification()
        lastFireMessage = "수동 발사: \(isoNow())"
        onFire?()
    }

    // MARK: - Private

    private func fire() {
        logger.info("자동 수집 Timer 발사")
        sendNotification()
        lastFireMessage = "자동 발사: \(isoNow())"
        onFire?()
        reschedule()
    }

    private func computeNextFireDate() -> Date {
        let cal = Calendar(identifier: .gregorian)
        var components = cal.dateComponents([.year, .month, .day], from: Date())
        components.hour = hourOfDay
        components.minute = 0
        components.second = 0

        guard let today = cal.date(from: components) else { return Date().addingTimeInterval(3600) }

        switch frequency {
        case .off:
            return today
        case .daily:
            if today > Date() { return today }
            return cal.date(byAdding: .day, value: 1, to: today) ?? today
        case .weekly:
            let todayWeekday = cal.component(.weekday, from: Date())  // 1=일 ~ 7=토
            let targetWeekday = weekday + 1  // Calendar 는 1-based
            var daysOffset = targetWeekday - todayWeekday
            if daysOffset < 0 { daysOffset += 7 }
            if daysOffset == 0 && today <= Date() { daysOffset = 7 }
            return cal.date(byAdding: .day, value: daysOffset, to: today) ?? today
        }
    }

    private func persist() {
        defaults.set(frequency.rawValue, forKey: keyFrequency)
        defaults.set(hourOfDay, forKey: keyHour)
        defaults.set(weekday, forKey: keyWeekday)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            if !granted {
                self?.logger.warning("UNNotification 권한 거부됨")
            }
        }
    }

    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "HealGuide — 자동 수집"
        content.body = "랭커 데이터 수집 시간입니다. HealGuide 를 열어 수집 탭에서 실행하세요."
        content.sound = .default

        let req = UNNotificationRequest(
            identifier: "autoCollect-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    private func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
