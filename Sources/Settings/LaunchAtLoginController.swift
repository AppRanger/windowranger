import Combine
import Foundation
import ServiceManagement

@MainActor
protocol LaunchAtLoginServicing {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
struct MainAppLaunchAtLoginService: LaunchAtLoginServicing {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Reads the current login-item state without mutating it. Registration changes happen only from
/// an explicit Settings toggle, which keeps app construction and non-hosted tests side-effect-free.
@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var errorMessage: String?

    private let service: LaunchAtLoginServicing

    convenience init() {
        self.init(service: MainAppLaunchAtLoginService())
    }

    init(service: LaunchAtLoginServicing) {
        self.service = service
        isEnabled = service.isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        do {
            try service.setEnabled(enabled)
            isEnabled = service.isEnabled
            errorMessage = nil
        } catch {
            isEnabled = service.isEnabled
            errorMessage = error.localizedDescription
        }
    }
}
