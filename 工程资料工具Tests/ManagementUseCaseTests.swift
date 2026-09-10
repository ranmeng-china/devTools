import XCTest
@testable import EngineeringDocumentTool

final class ManagementUseCaseTests: XCTestCase {
    func test工程骨架返回空管理快照() {
        let useCase = ManagementUseCase(store: MemoryManagementSnapshotStore())

        XCTAssertEqual(useCase.managementSnapshot(), .empty)
    }
}
