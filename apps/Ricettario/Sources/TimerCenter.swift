import SwiftUI
import UserNotifications
import AudioToolbox
import RicettarioCore

/// Kitchen timers: several at once, they keep running when the cooking
/// screen is closed; a local notification rings when the app is not open.
@MainActor
@Observable
final class TimerCenter {
    static let shared = TimerCenter()

    struct KitchenTimer: Identifiable, Equatable {
        let id: UUID
        var label: String
        var recipeTitle: String
        var stepID: UUID?
        var duration: Int
        /// Running: end date. Paused: nil and `pausedRemaining` set.
        var endDate: Date?
        var pausedRemaining: Int?

        var isPaused: Bool { endDate == nil }

        func remaining(at now: Date = Date()) -> Int {
            if let end = endDate { return max(0, Int(end.timeIntervalSince(now).rounded(.up))) }
            return pausedRemaining ?? 0
        }

        func isFinished(at now: Date = Date()) -> Bool { remaining(at: now) == 0 }
    }

    private(set) var timers: [KitchenTimer] = []
    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private var rung = Set<UUID>()
    @ObservationIgnored private let delegate = NotificationDelegate()

    private init() {}

    func installNotificationDelegate() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    func timer(for stepID: UUID) -> KitchenTimer? { timers.first { $0.stepID == stepID } }

    func start(label: String, recipeTitle: String, seconds: Int, stepID: UUID? = nil) {
        guard seconds > 0 else { return }
        if let stepID, let old = timer(for: stepID) { cancel(old.id) }
        let t = KitchenTimer(id: UUID(), label: label, recipeTitle: recipeTitle, stepID: stepID, duration: seconds,
                             endDate: Date().addingTimeInterval(TimeInterval(seconds)))
        timers.append(t)
        schedule(t)
        startTicking()
    }

    func pause(_ id: UUID) {
        guard let i = timers.firstIndex(where: { $0.id == id }), !timers[i].isPaused else { return }
        timers[i].pausedRemaining = timers[i].remaining()
        timers[i].endDate = nil
        unschedule(id)
    }

    func resume(_ id: UUID) {
        guard let i = timers.firstIndex(where: { $0.id == id }), timers[i].isPaused else { return }
        timers[i].endDate = Date().addingTimeInterval(TimeInterval(timers[i].pausedRemaining ?? 0))
        timers[i].pausedRemaining = nil
        schedule(timers[i])
        startTicking()
    }

    func add(_ id: UUID, seconds: Int) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        rung.remove(id)
        if let end = timers[i].endDate {
            timers[i].endDate = max(end, Date()).addingTimeInterval(TimeInterval(seconds))
            schedule(timers[i])
        } else {
            timers[i].pausedRemaining = (timers[i].pausedRemaining ?? 0) + seconds
        }
        timers[i].duration += seconds
        startTicking()
    }

    func cancel(_ id: UUID) {
        timers.removeAll { $0.id == id }
        rung.remove(id)
        unschedule(id)
    }

    // MARK: Ticking (in-app alarm)

    private func startTicking() {
        guard tick == nil else { return }
        tick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.check()
                if self.timers.allSatisfy({ $0.isPaused || self.rung.contains($0.id) }) {
                    self.tick = nil
                    return
                }
            }
        }
    }

    private func check() {
        let now = Date()
        for t in timers where !t.isPaused && t.isFinished(at: now) && !rung.contains(t.id) {
            rung.insert(t.id)
            // In foreground the notification banner rings too (delegate).
            AudioServicesPlaySystemSound(1005)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: Notifications

    private func schedule(_ t: KitchenTimer) {
        guard AppModel.shared.data.settings.timerNotifications, let end = t.endDate else { return }
        let center = UNUserNotificationCenter.current()
        let id = t.id.uuidString
        let label = t.label
        let title = t.recipeTitle
        let interval = max(1, end.timeIntervalSinceNow)
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "⏰ \(label)"
            content.body = "Tempo scaduto · \(title)"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    private func unschedule(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Running timers as chips (bottom of the app and in cooking mode).
struct TimerStrip: View {
    @Environment(TimerCenter.self) private var timers
    @Environment(\.m3) private var m3

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(timers.timers) { t in TimerChip(timer: t) }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }
}

struct TimerChip: View {
    @Environment(TimerCenter.self) private var timers
    @Environment(\.m3) private var m3
    let timer: TimerCenter.KitchenTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = timer.remaining(at: ctx.date)
            let done = left == 0
            let tones = done ? m3.errorTones : (timer.isPaused ? m3.neutral : m3.warningTones)
            Menu {
                if !done {
                    if timer.isPaused {
                        Button { timers.resume(timer.id) } label: { Label("Riprendi", systemImage: "play.fill") }
                    } else {
                        Button { timers.pause(timer.id) } label: { Label("Pausa", systemImage: "pause.fill") }
                    }
                }
                Button { timers.add(timer.id, seconds: 60) } label: { Label("+1 minuto", systemImage: "plus") }
                Button(role: .destructive) { timers.cancel(timer.id) } label: { Label(done ? "Chiudi" : "Annulla timer", systemImage: "xmark") }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: done ? "bell.and.waves.left.and.right.fill" : (timer.isPaused ? "pause.fill" : "timer"))
                        .symbolEffect(.pulse, isActive: done)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(done ? "Fatto!" : Fmt.clock(left)).font(.m3TitleSmall).monospacedDigit()
                        Text(timer.label).font(.m3LabelSmall).lineLimit(1)
                    }
                }
                .foregroundStyle(tones.onContainer)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(tones.container, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            }
        }
    }
}
