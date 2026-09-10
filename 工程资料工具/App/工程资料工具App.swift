import SwiftUI

@main
struct EngineeringDocumentToolApp: App {
    private let managementUseCase = ManagementUseCase(store: MemoryManagementSnapshotStore())

    var body: some Scene {
        MenuBarExtra("工程资料工具", systemImage: "doc.text") {
            MenuBarContentView(managementUseCase: managementUseCase)
        }

        Window("工程资料工具管理", id: "management") {
            ManagementWindowView(managementUseCase: managementUseCase)
        }
    }
}
