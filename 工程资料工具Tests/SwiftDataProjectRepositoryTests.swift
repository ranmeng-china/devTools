import SwiftData
import XCTest
@testable import EngineeringDocumentTool

@MainActor
final class SwiftDataProjectRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repository: SwiftDataProjectRepository!

    override func setUpWithError() throws {
        let schema = Schema([
            ProjectRecord.self, EnvironmentRecord.self, ServerRecord.self, ServerPortRecord.self,
            ServiceRecord.self, VPNResourceRecord.self, SystemEntryRecord.self, CredentialSetRecord.self,
            FieldRecord.self, FieldVersionRecord.self, SourceFragmentRecord.self, ChangeSetRecord.self,
            PendingItemRecord.self, BackupMetadataRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        repository = SwiftDataProjectRepository(context: context)
    }

    func test项目树与项目级资源关联() throws {
        let project = try repository.createProject(name: "虚构项目")
        let environment = try repository.addEnvironment(name: "测试", to: project)
        let server = try repository.addServer(name: "虚构服务器", serviceIPAddress: "192.0.2.10", to: environment)
        let service = try repository.addService(name: "虚构 Redis", kind: .redis, to: server)
        let vpn = VPNResourceRecord(name: "虚构 VPN", project: project)
        let system = SystemEntryRecord(name: "虚构系统", address: "https://example.invalid", project: project)
        context.insert(vpn)
        context.insert(system)
        try context.save()

        XCTAssertEqual(project.environments.first?.id, environment.id)
        XCTAssertEqual(environment.servers.first?.id, server.id)
        XCTAssertEqual(server.services.first?.id, service.id)
        XCTAssertEqual(project.vpnResources.count, 1)
        XCTAssertEqual(project.systemEntries.count, 1)
        XCTAssertEqual(try service.resolvedKind(), .redis)
    }

    func test每字段只保留三版且多字段独立裁剪() throws {
        let (fieldA, fieldB) = try makeTwoFields()
        for index in 1...4 {
            _ = try repository.confirm([FieldMutation(field: fieldA, value: "虚构值A\(index)", sourceFragment: "A\(index)")], ruleExplanation: "虚构规则")
        }
        _ = try repository.confirm([FieldMutation(field: fieldB, value: "虚构值B1", sourceFragment: "B1")], ruleExplanation: "虚构规则")

        XCTAssertEqual(fieldA.versions.map(\.sequence).sorted(), [2, 3, 4])
        XCTAssertEqual(fieldB.versions.map(\.sequence), [1])
    }

    func test裁剪清理片段与历史变更引用() throws {
        let field = try makeField()
        for index in 1...4 {
            _ = try repository.confirm([FieldMutation(field: field, value: "虚构值\(index)", sourceFragment: "片段\(index)")], ruleExplanation: "虚构规则")
        }
        let changeSets = try context.fetch(FetchDescriptor<ChangeSetRecord>())

        XCTAssertEqual(field.versions.count, 3)
        XCTAssertFalse(changeSets.flatMap(\.versionReferences).contains { $0.sequence == 1 })
        XCTAssertFalse(changeSets.flatMap(\.fragmentReferences).contains { $0.content == "片段1" })
    }

    func test恢复历史创建新版本和新变更集() throws {
        let field = try makeField()
        _ = try repository.confirm([FieldMutation(field: field, value: "虚构旧值", sourceFragment: "旧片段")], ruleExplanation: "虚构规则")
        let oldVersion = try XCTUnwrap(field.versions.first)
        _ = try repository.confirm([FieldMutation(field: field, value: "虚构新值", sourceFragment: "新片段")], ruleExplanation: "虚构规则")
        let restoration = try repository.restore(oldVersion, ruleExplanation: "恢复虚构值")

        XCTAssertEqual(restoration.operation, "恢复历史版本")
        XCTAssertEqual(field.versions.count, 3)
        XCTAssertEqual(field.versions.first(where: { $0.sequence == 3 })?.value, "虚构旧值")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChangeSetRecord>()).count, 3)
    }

    func test变更集只引用版本和片段而不保存敏感值() throws {
        let field = try makeField()
        let sensitiveValue = "虚构🔐密码\n保持原样"
        let changeSet = try repository.confirm([FieldMutation(field: field, value: sensitiveValue, sourceFragment: "仅此字段片段")], ruleExplanation: "字段更新")

        XCTAssertEqual(changeSet.versionReferences.count, 1)
        XCTAssertEqual(changeSet.fragmentReferences.count, 1)
        XCTAssertEqual(changeSet.versionReferences.first?.value, sensitiveValue)
        XCTAssertFalse(changeSet.ruleExplanation.contains(sensitiveValue))
    }

    func test待整理替换转正和删除() throws {
        let project = try repository.createProject(name: "虚构项目")
        let first = try repository.replacePendingItem(nil, rawText: "虚构待整理一", in: project)
        let second = try repository.replacePendingItem(first, rawText: "虚构待整理二", in: project)
        XCTAssertEqual(project.pendingItems.count, 1)
        let field = try makeField(in: project)
        _ = try repository.confirm([FieldMutation(field: field, value: "虚构值", sourceFragment: "虚构片段")], ruleExplanation: "转结构化字段", removing: second)
        XCTAssertEqual(project.pendingItems.count, 0)
        let third = try repository.replacePendingItem(nil, rawText: "虚构待删除", in: project)
        try repository.deletePendingItem(third)
        XCTAssertEqual(project.pendingItems.count, 0)
    }

    func test敏感值逐字符保真与保存失败回滚() throws {
        let field = try makeField()
        let original = "虚构A\u{0301}🔐\n终端空格 "
        _ = try repository.confirm([FieldMutation(field: field, value: original, sourceFragment: "最小片段")], ruleExplanation: "虚构规则")
        XCTAssertEqual(field.versions.first?.value, original)

        let failingRepository = SwiftDataProjectRepository(context: context) { throw PersistenceTransactionError.forcedFailure }
        XCTAssertThrowsError(try failingRepository.confirm([FieldMutation(field: field, value: "不应保存", sourceFragment: "不应保存")], ruleExplanation: "虚构规则"))
        XCTAssertEqual(field.versions.count, 1)
        XCTAssertEqual(field.versions.first?.value, original)
    }

    func test裁剪后旧版本与片段从全新上下文物理消失() throws {
        let field = try makeField()
        _ = try repository.confirm([FieldMutation(field: field, value: "虚构值1", sourceFragment: "虚构片段1")], ruleExplanation: "虚构规则")
        let removedVersionID: UUID = try XCTUnwrap(field.versions.first?.id)
        let removedFragmentID: UUID = try XCTUnwrap(field.versions.first?.sourceFragment.id)
        for index in 2...4 {
            _ = try repository.confirm([FieldMutation(field: field, value: "虚构值\(index)", sourceFragment: "虚构片段\(index)")], ruleExplanation: "虚构规则")
        }
        let fresh = ModelContext(container)
        let versionDescriptor = FetchDescriptor<FieldVersionRecord>(predicate: #Predicate { $0.id == removedVersionID })
        let fragmentDescriptor = FetchDescriptor<SourceFragmentRecord>(predicate: #Predicate { $0.id == removedFragmentID })
        let changeSets = try fresh.fetch(FetchDescriptor<ChangeSetRecord>())
        XCTAssertTrue(try fresh.fetch(versionDescriptor).isEmpty)
        XCTAssertTrue(try fresh.fetch(fragmentDescriptor).isEmpty)
        XCTAssertFalse(changeSets.flatMap(\.versionReferences).contains { $0.id == removedVersionID })
        XCTAssertFalse(changeSets.flatMap(\.fragmentReferences).contains { $0.id == removedFragmentID })
    }

    func test待整理旧记录在替换转正删除后从全新上下文消失() throws {
        let project = try repository.createProject(name: "虚构项目")
        let first = try repository.replacePendingItem(nil, rawText: "虚构待整理一", in: project)
        let firstID = first.id
        let second = try repository.replacePendingItem(first, rawText: "虚构待整理二", in: project)
        let secondID = second.id
        let field = try makeField(in: project)
        _ = try repository.confirm([FieldMutation(field: field, value: "虚构值", sourceFragment: "虚构片段")], ruleExplanation: "转正", removing: second)
        let third = try repository.replacePendingItem(nil, rawText: "虚构待删除", in: project)
        let thirdID = third.id
        try repository.deletePendingItem(third)
        let fresh = ModelContext(container)
        for identifier in [firstID, secondID, thirdID] {
            let descriptor = FetchDescriptor<PendingItemRecord>(predicate: #Predicate { $0.id == identifier })
            XCTAssertTrue(try fresh.fetch(descriptor).isEmpty)
        }
    }

    func test失败回滚后新上下文实体计数不变() throws {
        let field = try makeField()
        _ = try repository.confirm([FieldMutation(field: field, value: "虚构初值", sourceFragment: "虚构初片段")], ruleExplanation: "虚构规则")
        let before = try entityCounts(in: ModelContext(container))
        let failing = SwiftDataProjectRepository(context: context) { throw PersistenceTransactionError.forcedFailure }
        XCTAssertThrowsError(try failing.confirm([FieldMutation(field: field, value: "虚构失败值", sourceFragment: "虚构失败片段")], ruleExplanation: "虚构规则"))
        let fresh = ModelContext(container)
        XCTAssertEqual(try entityCounts(in: fresh), before)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<FieldVersionRecord>(predicate: #Predicate { $0.value == "虚构失败值" })).isEmpty)
    }

    func testUnicode跨保存重取后按标量保真且非法服务类型显式失败() throws {
        let field = try makeField()
        let original = "虚构A\u{0301}🔐\n末尾 "
        _ = try repository.confirm([FieldMutation(field: field, value: original, sourceFragment: "虚构片段")], ruleExplanation: "虚构规则")
        let versionID = try XCTUnwrap(field.versions.first?.id)
        let fresh = ModelContext(container)
        let fetched = try XCTUnwrap(fresh.fetch(FetchDescriptor<FieldVersionRecord>(predicate: #Predicate { $0.id == versionID })).first)
        XCTAssertEqual(fetched.value.unicodeScalars.map(\.value), original.unicodeScalars.map(\.value))
        XCTAssertThrowsError(try ServiceKind.parsePersisted("invalid-service"))
        XCTAssertEqual(try ServiceKind.parsePersisted("nginx"), .nginx)
    }

    func test非法确认与凭据单Owner在写入前被拒绝() throws {
        let firstProject = try repository.createProject(name: "虚构项目一")
        let secondProject = try repository.createProject(name: "虚构项目二")
        let firstField = try makeField(in: firstProject)
        let secondField = try makeField(in: secondProject)
        let before = try entityCounts(in: ModelContext(container))
        XCTAssertThrowsError(try repository.confirm([FieldMutation(field: firstField, value: "一", sourceFragment: "一"), FieldMutation(field: firstField, value: "二", sourceFragment: "二")], ruleExplanation: "重复字段"))
        XCTAssertThrowsError(try repository.confirm([FieldMutation(field: firstField, value: "一", sourceFragment: "一"), FieldMutation(field: secondField, value: "二", sourceFragment: "二")], ruleExplanation: "跨项目"))
        let pending = try repository.replacePendingItem(nil, rawText: "虚构待整理", in: secondProject)
        XCTAssertThrowsError(try repository.confirm([FieldMutation(field: firstField, value: "一", sourceFragment: "一")], ruleExplanation: "错项目", removing: pending))
        let after = try entityCounts(in: ModelContext(container))
        XCTAssertEqual(after.versions, before.versions)
        XCTAssertEqual(after.fragments, before.fragments)
        XCTAssertEqual(after.changes, before.changes)
        let serverCredential = CredentialSetRecord(name: "虚构服务器凭据", owner: .server(try XCTUnwrap(firstField.service?.server)))
        let serviceCredential = CredentialSetRecord(name: "虚构服务凭据", owner: .service(try XCTUnwrap(firstField.service)))
        let vpnCredential = CredentialSetRecord(name: "虚构VPN凭据", owner: .vpn(VPNResourceRecord(name: "虚构VPN", project: firstProject)))
        let systemCredential = CredentialSetRecord(name: "虚构系统凭据", owner: .systemEntry(SystemEntryRecord(name: "虚构系统", address: "https://example.invalid", project: firstProject)))
        for credential in [serverCredential, serviceCredential, vpnCredential, systemCredential] { XCTAssertEqual(credential.ownerCount, 1); XCTAssertEqual(credential.project?.id, firstProject.id) }
        let serverField = try repository.addField(name: "服务器字段", owner: .server(try XCTUnwrap(firstField.service?.server)))
        let serviceField = try repository.addField(name: "服务字段", owner: .service(try XCTUnwrap(firstField.service)))
        let credentialField = try repository.addField(name: "凭据字段", owner: .credentialSet(try repository.addCredentialSet(name: "仓储凭据", owner: .server(try XCTUnwrap(firstField.service?.server)))))
        for field in [serverField, serviceField, credentialField] { XCTAssertEqual(field.ownerCount, 1); XCTAssertEqual(field.project?.id, firstProject.id) }
    }

    func test新上下文审计空变更和受控版本片段关系() throws {
        let field = try makeField()
        let projectID = try XCTUnwrap(field.project?.id)
        let before = try entityCounts(in: ModelContext(container))
        XCTAssertThrowsError(try repository.confirm([], ruleExplanation: "空变更"))
        XCTAssertEqual(try entityCounts(in: ModelContext(container)), before)
        let changeSet = try repository.confirm([FieldMutation(field: field, value: "虚构值", sourceFragment: "虚构片段")], ruleExplanation: "虚构规则")
        let changeID = changeSet.id
        let fresh = ModelContext(container)
        let fetched = try XCTUnwrap(fresh.fetch(FetchDescriptor<ChangeSetRecord>(predicate: #Predicate { $0.id == changeID })).first)
        XCTAssertEqual(fetched.project?.id, projectID)
        XCTAssertEqual(fetched.affectedFieldCount, 1)
        let version = try XCTUnwrap(fetched.versionReferences.first)
        XCTAssertEqual(version.sourceFragment.version?.id, version.id)
        XCTAssertEqual(fetched.fragmentReferences.first?.id, version.sourceFragment.id)
    }

    func test整库备份元数据与仓储服务器凭据可在新上下文重取() throws {
        let field = try makeField()
        let server = try XCTUnwrap(field.service?.server)
        let metadata = try repository.recordBackupMetadata(formatVersion: 1, checksum: "虚构校验值")
        let credential = try repository.addCredentialSet(name: "虚构服务器凭据", owner: .server(server))
        let metadataID = metadata.id
        let credentialID = credential.id
        let fresh = ModelContext(container)
        let fetchedMetadata = try XCTUnwrap(fresh.fetch(FetchDescriptor<BackupMetadataRecord>(predicate: #Predicate { $0.id == metadataID })).first)
        let fetchedCredential = try XCTUnwrap(fresh.fetch(FetchDescriptor<CredentialSetRecord>(predicate: #Predicate { $0.id == credentialID })).first)
        XCTAssertEqual(fetchedMetadata.formatVersion, 1)
        XCTAssertEqual(fetchedMetadata.checksum, "虚构校验值")
        XCTAssertNotNil(fetchedMetadata.createdAt)
        XCTAssertEqual(fetchedCredential.ownerCount, 1)
        XCTAssertEqual(fetchedCredential.server?.id, server.id)
        XCTAssertEqual(fetchedCredential.project?.id, field.project?.id)
    }

    func test跨项目待整理与审计污染失败后数据不变() throws {
        let first = try repository.createProject(name: "虚构项目一")
        let second = try repository.createProject(name: "虚构项目二")
        let field = try makeField(in: first)
        let pending = try repository.replacePendingItem(nil, rawText: "虚构完整原文", in: first)
        let pendingID = pending.id
        let secondProjectID = second.id
        let before = try entityCounts(in: ModelContext(container))
        XCTAssertThrowsError(try repository.replacePendingItem(pending, rawText: "不应替换", in: second))
        XCTAssertThrowsError(try repository.confirm([FieldMutation(field: field, value: "虚构敏感值", sourceFragment: "片段")], ruleExplanation: "虚构敏感值", removing: pending))
        XCTAssertThrowsError(try repository.confirm([FieldMutation(field: field, value: "另一值", sourceFragment: "片段")], ruleExplanation: "虚构完整原文", removing: pending))
        let fresh = ModelContext(container)
        XCTAssertEqual(try entityCounts(in: fresh), before)
        XCTAssertFalse(try fresh.fetch(FetchDescriptor<PendingItemRecord>(predicate: #Predicate { $0.id == pendingID })).isEmpty)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<PendingItemRecord>(predicate: #Predicate { $0.project?.id == secondProjectID })).isEmpty)
    }

    func test历史敏感值污染审计解释被拒绝且持久数据不变() throws {
        let field = try makeField()
        _ = try repository.confirm([FieldMutation(field: field, value: "虚构旧敏感值", sourceFragment: "旧片段")], ruleExplanation: "首次保存")
        let oldVersionID = try XCTUnwrap(field.versions.first?.id)
        let before = try entityCounts(in: ModelContext(container))
        XCTAssertThrowsError(try repository.confirm([FieldMutation(field: field, value: "虚构新敏感值", sourceFragment: "新片段")], ruleExplanation: "解释含虚构旧敏感值"))
        let fresh = ModelContext(container)
        XCTAssertEqual(try entityCounts(in: fresh), before)
        let oldVersion = try XCTUnwrap(fresh.fetch(FetchDescriptor<FieldVersionRecord>(predicate: #Predicate { $0.id == oldVersionID })).first)
        XCTAssertEqual(oldVersion.value, "虚构旧敏感值")
    }

    private func makeField() throws -> FieldRecord {
        try makeField(in: try repository.createProject(name: "虚构项目"))
    }

    private func makeField(in project: ProjectRecord) throws -> FieldRecord {
        let environment = try repository.addEnvironment(name: "测试", to: project)
        let server = try repository.addServer(name: "虚构服务器", serviceIPAddress: "192.0.2.20", to: environment)
        let service = try repository.addService(name: "虚构 MySQL", kind: .mysql, to: server)
        return try repository.addField(name: "密码", owner: .service(service))
    }

    private struct EntityCounts: Equatable {
        let versions: Int
        let fragments: Int
        let changes: Int
    }

    private func entityCounts(in context: ModelContext) throws -> EntityCounts {
        EntityCounts(
            versions: try context.fetchCount(FetchDescriptor<FieldVersionRecord>()),
            fragments: try context.fetchCount(FetchDescriptor<SourceFragmentRecord>()),
            changes: try context.fetchCount(FetchDescriptor<ChangeSetRecord>())
        )
    }

    private func makeTwoFields() throws -> (FieldRecord, FieldRecord) {
        let first = try makeField()
        let second = try repository.addField(name: "令牌", owner: .service(try XCTUnwrap(first.service)))
        return (first, second)
    }
}
