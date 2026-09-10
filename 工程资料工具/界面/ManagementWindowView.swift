import SwiftUI

/// 管理窗口承载低频管理信息；当前只展示由用例层提供的启动快照。
struct ManagementWindowView: View {
    let managementUseCase: ManagementUseCase

    var body: some View {
        let snapshot = managementUseCase.managementSnapshot()

        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 32))
            Text("尚未创建项目")
                .font(.title3)
            Text("当前项目数量：\(snapshot.projectCount)。项目管理功能将在后续任务中实现。")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 420, minHeight: 260)
        .padding()
    }
}
