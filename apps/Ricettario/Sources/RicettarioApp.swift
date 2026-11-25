import SwiftUI
import BackgroundTasks
import RicettarioCore

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: AppModel.backupTaskID, using: nil) { task in
            let work = Task { @MainActor in
                await CloudBackupService.shared.backup(force: false)
                CloudBackupService.scheduleBackgroundRefresh()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
        MainActor.assumeIsolated {
            _ = AppModel.shared
            TimerCenter.shared.installNotificationDelegate()
        }
        return true
    }
}

@main
struct RicettarioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared
    @State private var cloud = CloudBackupService.shared
    @State private var timers = TimerCenter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .environment(model)
                .environment(cloud)
                .environment(timers)
                .onOpenURL { model.handle(url: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.setActive(true)
            case .background: model.setActive(false)
            default: break
            }
        }
    }
}

/// Material palette from the chosen seed color and the appearance.
private struct ThemedRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var systemScheme

    private var scheme: ColorScheme {
        switch model.data.settings.appearance {
        case .system: return systemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        let theme = M3Theme(seed: model.seedColor, dark: scheme == .dark)
        RootView()
            .environment(\.m3, theme)
            .tint(theme.primary)
            .fontDesign(.rounded)
            .preferredColorScheme(model.data.settings.appearance == .system ? nil : scheme)
            .animation(.easeInOut(duration: 0.4), value: model.seedColor)
    }
}
