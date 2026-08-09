import Combine
import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    var isRegistered: Bool {
        self == .enabled || self == .requiresApproval
    }
}

@MainActor
protocol LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

@MainActor
struct MainAppLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .notFound
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Reads the current login-item state without mutating it. Registration changes happen only from
/// an explicit Settings toggle, which keeps app construction and non-hosted tests side-effect-free.
@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var status: LaunchAtLoginStatus
    @Published private(set) var errorMessage: String?

    private let service: LaunchAtLoginServicing

    var isEnabled: Bool { status.isRegistered }

    var statusMessage: String? {
        switch status {
        case .notRegistered:
            nil
        case .enabled:
            "WindowManager will open automatically when you sign in."
        case .requiresApproval:
            "Registered, but macOS requires approval in System Settings before WindowManager can open at login."
        case .notFound:
            "macOS could not find a login item for this build. Quit and relaunch the current signed app, then try again."
        }
    }

    convenience init() {
        self.init(service: MainAppLaunchAtLoginService())
    }

    init(service: LaunchAtLoginServicing) {
        self.service = service
        status = service.status
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        do {
            try service.setEnabled(enabled)
            status = service.status
            errorMessage = nil
        } catch {
            status = service.status
            errorMessage = status.isRegistered ? nil : error.localizedDescription
        }
    }

    func refresh() {
        status = service.status
        if status != .notFound {
            errorMessage = nil
        }
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
