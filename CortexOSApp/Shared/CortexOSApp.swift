//
//  CortexOSApp.swift
//  CortexOS
//
//  Multiplatform SwiftUI App entry point.
//  Builds for both iOS 17+ and macOS 14+.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct CortexOSApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(SimpliXioAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif

        // macOS Settings uses the standard SwiftUI Settings scene. iCloud and
        // preview preferences persist through UserDefaults across instances.
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(CortexEngine())
                .frame(width: 500, height: 400)
        }
        #endif
    }
}

#if os(iOS)
@MainActor
final class SimpliXioRouteCenter: ObservableObject {
    static let shared = SimpliXioRouteCenter()

    enum Route: Equatable {
        case focus
        case capture
    }

    @Published var pendingRoute: Route?

    func handle(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "simplixio" else { return }
        let target = (url.host ?? "").lowercased()
        switch target {
        case "capture":
            pendingRoute = .capture
        case "focus", "today":
            pendingRoute = .focus
        default:
            break
        }
    }

    func handleShortcut(type: String) {
        switch type {
        case "com.simplixio.capture", "com.simplixio.note":
            pendingRoute = .capture
        case "com.simplixio.today":
            pendingRoute = .focus
        default:
            break
        }
    }
}

final class SimpliXioSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let shortcutItem = connectionOptions.shortcutItem {
            SimpliXioRouteCenter.shared.handleShortcut(type: shortcutItem.type)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        SimpliXioRouteCenter.shared.handleShortcut(type: shortcutItem.type)
        completionHandler(true)
    }
}

final class SimpliXioAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = SimpliXioSceneDelegate.self
        }
        return configuration
    }
}
#endif
