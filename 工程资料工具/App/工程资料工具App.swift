import SwiftUI
import SwiftData

@main
@MainActor
struct EngineeringDocumentToolApp: App {
    private let persistenceContainer: ModelContainer
    private let managementUseCase: ManagementUseCase

    init() {
        let container = ApplicationPersistence.makeContainer()
        persistenceContainer = container
        managementUseCase = ManagementUseCase(store: SwiftDataProjectRepository(context: ModelContext(container)))
    }

    var body: some Scene {
        MenuBarExtra("工程资料工具", systemImage: "doc.text") {
            MenuBarContentView(managementUseCase: managementUseCase)
        }

        Window("工程资料工具管理", id: "management") {
            ManagementWindowView(managementUseCase: managementUseCase)
        }
        .modelContainer(persistenceContainer)
    }
}
