import Foundation
import SwiftData

struct FieldMutation {
    let field: FieldRecord
    let value: String
    let sourceFragment: String
}

enum PersistenceTransactionError: Error {
    case forcedFailure
}

enum ChangeOperation: String {
    case confirmation = "确认变更"
    case restoration = "恢复历史版本"
}

/// 所有确认、裁剪和引用清理均从此仓储入口在一次保存中完成。
@MainActor final class SwiftDataProjectRepository: ManagementSnapshotStore {
    private let context: ModelContext
    private let beforeSave: () throws -> Void

    init(context: ModelContext, beforeSave: @escaping () throws -> Void = {}) {
        self.context = context
        context.autosaveEnabled = false
        self.beforeSave = beforeSave
    }

    func loadManagementSnapshot() -> ManagementSnapshot {
        let projects = (try? context.fetch(FetchDescriptor<ProjectRecord>())) ?? []
        return ManagementSnapshot(projectCount: projects.count)
    }

    @discardableResult
    func createProject(name: String) throws -> ProjectRecord {
        try performAtomically {
            let project = ProjectRecord(name: name)
            context.insert(project)
            return project
        }
    }

    @discardableResult
    func addEnvironment(name: String, role: EnvironmentRole = .regular, to project: ProjectRecord) throws -> EnvironmentRecord {
        try performAtomically {
            let environment = EnvironmentRecord(name: name, role: role, project: project)
            context.insert(environment)
            return environment
        }
    }

    @discardableResult
    func addServer(name: String, serviceIPAddress: String, firewallSourceIPAddress: String? = nil, role: ServerRole = .regular, to environment: EnvironmentRecord) throws -> ServerRecord {
        try performAtomically {
            let server = ServerRecord(name: name, serviceIPAddress: serviceIPAddress, firewallSourceIPAddress: firewallSourceIPAddress, role: role, environment: environment)
            context.insert(server)
            return server
        }
    }

    @discardableResult
    func addService(name: String, kind: ServiceKind, to server: ServerRecord) throws -> ServiceRecord {
        try performAtomically {
            let service = ServiceRecord(name: name, kind: kind, server: server)
            context.insert(service)
            return service
        }
    }

    @discardableResult
    func confirm(_ mutations: [FieldMutation], operation: ChangeOperation = .confirmation, ruleExplanation: String, removing pendingItem: PendingItemRecord? = nil) throws -> ChangeSetRecord {
        try performAtomically {
            guard let project = mutations.first?.field.project, !mutations.isEmpty else { throw PersistenceTransactionError.forcedFailure }
            guard Set(mutations.map { $0.field.id }).count == mutations.count else { throw PersistenceTransactionError.forcedFailure }
            guard mutations.allSatisfy({ $0.field.project?.id == project.id }) else { throw PersistenceTransactionError.forcedFailure }
            guard mutations.allSatisfy({ $0.field.ownerCount == 1 }) else { throw PersistenceTransactionError.forcedFailure }
            guard pendingItem == nil || pendingItem?.project?.id == project.id else { throw PersistenceTransactionError.forcedFailure }
            guard !containsProtectedContent(in: ruleExplanation, mutations: mutations, pendingItem: pendingItem) else { throw PersistenceTransactionError.forcedFailure }
            let changeSet = ChangeSetRecord(project: project, operation: operation.rawValue, ruleExplanation: ruleExplanation, affectedFieldCount: mutations.count)
            context.insert(changeSet)

            for mutation in mutations {
                let nextSequence = (mutation.field.versions.map(\.sequence).max() ?? 0) + 1
                let (version, fragment) = FieldVersionPairFactory.make(sequence: nextSequence, value: mutation.value, field: mutation.field, fragmentContent: mutation.sourceFragment)
                context.insert(fragment)
                context.insert(version)
                try trimVersions(for: mutation.field)
                changeSet.versionReferences.append(version)
                changeSet.fragmentReferences.append(fragment)
            }

            if let pendingItem {
                context.delete(pendingItem)
            }
            return changeSet
        }
    }

    @discardableResult
    func restore(_ version: FieldVersionRecord, ruleExplanation: String) throws -> ChangeSetRecord {
        let field = version.field
        let fragment = version.sourceFragment
        return try confirm(
            [FieldMutation(field: field, value: version.value, sourceFragment: fragment.content)],
            operation: .restoration,
            ruleExplanation: ruleExplanation
        )
    }

    @discardableResult
    func replacePendingItem(_ current: PendingItemRecord?, rawText: String, in project: ProjectRecord) throws -> PendingItemRecord {
        try performAtomically {
            guard current == nil || current?.project?.id == project.id else {
                throw PersistenceTransactionError.forcedFailure
            }
            if let current {
                context.delete(current)
            }
            let replacement = PendingItemRecord(currentRawText: rawText, project: project)
            context.insert(replacement)
            return replacement
        }
    }

    func deletePendingItem(_ item: PendingItemRecord) throws {
        try performAtomically {
            context.delete(item)
        }
    }

    @discardableResult
    func addCredentialSet(name: String, owner: CredentialOwner) throws -> CredentialSetRecord {
        try performAtomically {
            let credential = CredentialSetRecord(name: name, owner: owner)
            guard credential.ownerCount == 1, credential.project != nil else { throw PersistenceTransactionError.forcedFailure }
            context.insert(credential)
            return credential
        }
    }

    @discardableResult
    func addField(name: String, owner: FieldOwner) throws -> FieldRecord {
        try performAtomically {
            let field = FieldRecord(name: name, owner: owner)
            guard field.ownerCount == 1, field.project != nil else { throw PersistenceTransactionError.forcedFailure }
            context.insert(field)
            return field
        }
    }

    @discardableResult
    func recordBackupMetadata(formatVersion: Int, checksum: String) throws -> BackupMetadataRecord {
        try performAtomically {
            let metadata = BackupMetadataRecord(formatVersion: formatVersion, checksum: checksum)
            context.insert(metadata)
            return metadata
        }
    }

    private func trimVersions(for field: FieldRecord) throws {
        let discarded = field.versions.sorted { $0.sequence < $1.sequence }.dropLast(3)
        guard !discarded.isEmpty else { return }

        let allChangeSets = try context.fetch(FetchDescriptor<ChangeSetRecord>())
        for version in discarded {
            let fragment = version.sourceFragment
            for changeSet in allChangeSets {
                changeSet.versionReferences.removeAll { $0.id == version.id }
                changeSet.fragmentReferences.removeAll { $0.id == fragment.id }
            }
            field.versions.removeAll { $0.id == version.id }
            context.delete(fragment)
            context.delete(version)
        }
    }

    /// 审计解释不能复制本次、历史或待整理的完整敏感内容。
    private func containsProtectedContent(in explanation: String, mutations: [FieldMutation], pendingItem: PendingItemRecord?) -> Bool {
        let mutationValues = mutations.map(\.value)
        let historicalValues = mutations.flatMap { $0.field.versions.map(\.value) }
        let pendingValues = pendingItem.map { [$0.currentRawText] } ?? []
        return (mutationValues + historicalValues + pendingValues)
            .filter { !$0.isEmpty }
            .contains { explanation.contains($0) }
    }

    private func performAtomically<T>(_ operation: () throws -> T) throws -> T {
        do {
            let result = try operation()
            try beforeSave()
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }
}
