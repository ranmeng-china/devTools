import Foundation

/// 将界面层与数据来源隔离的最小管理用例。
@MainActor
struct ManagementUseCase {
    private let store: any ManagementSnapshotStore

    init(store: any ManagementSnapshotStore) {
        self.store = store
    }

    func managementSnapshot() -> ManagementSnapshot {
        store.loadManagementSnapshot()
    }
}
