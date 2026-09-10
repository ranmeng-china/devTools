import Foundation

/// 工程启动阶段的内存数据源，不承担持久化职责。
struct MemoryManagementSnapshotStore: ManagementSnapshotStore {
    func loadManagementSnapshot() -> ManagementSnapshot {
        .empty
    }
}
