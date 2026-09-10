import AppKit
import SwiftUI

/// 菜单栏只保留入口职责，避免承载低频管理内容。
struct MenuBarContentView: View {
    let managementUseCase: ManagementUseCase

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开管理窗口") {
            _ = managementUseCase.managementSnapshot()
            openWindow(id: "management")
        }

        Divider()

        Button("退出工程资料工具") {
            NSApplication.shared.terminate(nil)
        }
    }
}
