import Foundation

/// 管理窗口在工程骨架阶段唯一需要的领域状态。
struct ManagementSnapshot: Equatable {
    let projectCount: Int

    static let empty = ManagementSnapshot(projectCount: 0)
}

/// 用例层依赖此协议，存储层在基础设施侧提供实现。
protocol ManagementSnapshotStore {
    func loadManagementSnapshot() -> ManagementSnapshot
}
