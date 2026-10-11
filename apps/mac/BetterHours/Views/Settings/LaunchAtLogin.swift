import Observation
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

@Observable @MainActor
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status
    private var failure: String?
    private let service: any LoginItemService

    init(service: any LoginItemService = SMAppService.mainApp) {
        self.service = service
        status = service.status
    }

    var isOn: Bool { status == .enabled }

    var message: String? {
        if let failure { return failure }
        return status == .requiresApproval ? "Approve Better Hours in System Settings, General, Login Items." : nil
    }

    func refresh() {
        status = service.status
        failure = nil
    }

    func set(_ enabled: Bool) {
        do {
            if enabled { try service.register() } else { try service.unregister() }
            refresh()
        } catch {
            status = service.status
            failure = error.localizedDescription
        }
    }
}
