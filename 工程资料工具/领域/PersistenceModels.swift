import Foundation
import SwiftData

/// 受支持服务类型，持久化损坏值必须显式失败。
enum ServiceKind: String, CaseIterable, Codable {
    case mysql
    case redis
    case nginx

    static func parsePersisted(_ rawValue: String) throws -> ServiceKind {
        guard let kind = ServiceKind(rawValue: rawValue) else {
            throw ServiceKindDecodingError.unknownRawValue
        }
        return kind
    }
}

/// 服务类型持久化值不在白名单时的错误。
enum ServiceKindDecodingError: Error {
    case unknownRawValue
}

/// 环境的正常与未分类语义。
enum EnvironmentRole: String, Codable {
    case regular
    case uncategorized
}

/// 服务器的正常与待归属语义。
enum ServerRole: String, Codable {
    case regular
    case pendingAssignment
}

/// 项目为树、待整理项和变更审计的归属根。
@Model
final class ProjectRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var lastUsedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \EnvironmentRecord.project) var environments: [EnvironmentRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \VPNResourceRecord.project) var vpnResources: [VPNResourceRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \SystemEntryRecord.project) var systemEntries: [SystemEntryRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \PendingItemRecord.project) var pendingItems: [PendingItemRecord] = []
    /// 每个变更集必须明确归属一个项目。
    @Relationship(deleteRule: .cascade, inverse: \ChangeSetRecord.project) var changeSets: [ChangeSetRecord] = []

    init(name: String, lastUsedAt: Date = .now) {
        id = UUID()
        self.name = name
        self.lastUsedAt = lastUsedAt
    }
}

/// 项目中的环境节点。
@Model
final class EnvironmentRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    private(set) var roleRaw: String
    var project: ProjectRecord?
    @Relationship(deleteRule: .cascade, inverse: \ServerRecord.environment) var servers: [ServerRecord] = []
    var role: EnvironmentRole? { EnvironmentRole(rawValue: roleRaw) }

    init(name: String, role: EnvironmentRole = .regular, project: ProjectRecord) {
        id = UUID()
        self.name = name
        roleRaw = role.rawValue
        self.project = project
    }
}

/// 环境中的服务器节点，包含独立服务端与来源 IP。
@Model
final class ServerRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var serviceIPAddress: String
    var firewallSourceIPAddress: String?
    private(set) var roleRaw: String
    var environment: EnvironmentRecord?
    @Relationship(deleteRule: .cascade, inverse: \ServerPortRecord.server) var ports: [ServerPortRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \ServiceRecord.server) var services: [ServiceRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \CredentialSetRecord.server) var credentialSets: [CredentialSetRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \FieldRecord.server) var fields: [FieldRecord] = []
    var role: ServerRole? { ServerRole(rawValue: roleRaw) }

    init(name: String, serviceIPAddress: String, firewallSourceIPAddress: String? = nil, role: ServerRole = .regular, environment: EnvironmentRecord) {
        id = UUID()
        self.name = name
        self.serviceIPAddress = serviceIPAddress
        self.firewallSourceIPAddress = firewallSourceIPAddress
        roleRaw = role.rawValue
        self.environment = environment
    }
}

/// 服务器端口条目。
@Model
final class ServerPortRecord {
    @Attribute(.unique) var id: UUID
    var label: String
    var number: Int
    var server: ServerRecord?

    init(label: String, number: Int, server: ServerRecord) {
        id = UUID()
        self.label = label
        self.number = number
        self.server = server
    }
}

/// 服务器下的受限类型服务。
@Model
final class ServiceRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    private(set) var kindRaw: String
    var server: ServerRecord?
    @Relationship(deleteRule: .cascade, inverse: \CredentialSetRecord.service) var credentialSets: [CredentialSetRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \FieldRecord.service) var fields: [FieldRecord] = []

    /// 常规读取必须显式处理损坏的持久化类型。
    func resolvedKind() throws -> ServiceKind {
        try ServiceKind.parsePersisted(kindRaw)
    }

    init(name: String, kind: ServiceKind, server: ServerRecord) {
        id = UUID()
        self.name = name
        kindRaw = kind.rawValue
        self.server = server
    }
}

/// 项目级 VPN 资源。
@Model
final class VPNResourceRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var project: ProjectRecord?
    @Relationship(deleteRule: .cascade, inverse: \CredentialSetRecord.vpnResource) var credentialSets: [CredentialSetRecord] = []

    init(name: String, project: ProjectRecord) {
        id = UUID()
        self.name = name
        self.project = project
    }
}

/// 项目级系统入口。
@Model
final class SystemEntryRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var address: String
    var project: ProjectRecord?
    @Relationship(deleteRule: .cascade, inverse: \CredentialSetRecord.systemEntry) var credentialSets: [CredentialSetRecord] = []

    init(name: String, address: String, project: ProjectRecord) {
        id = UUID()
        self.name = name
        self.address = address
        self.project = project
    }
}

/// 凭据唯一所有者；公开构造不能产生零或多个 owner。
enum CredentialOwner {
    case server(ServerRecord)
    case service(ServiceRecord)
    case vpn(VPNResourceRecord)
    case systemEntry(SystemEntryRecord)
}

/// 可登录资源的一组命名凭据。
@Model
final class CredentialSetRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    private(set) var server: ServerRecord?
    private(set) var service: ServiceRecord?
    private(set) var vpnResource: VPNResourceRecord?
    private(set) var systemEntry: SystemEntryRecord?
    @Relationship(deleteRule: .cascade, inverse: \FieldRecord.credentialSet) var fields: [FieldRecord] = []

    init(name: String, owner: CredentialOwner) {
        id = UUID()
        self.name = name
        switch owner {
        case .server(let value): server = value
        case .service(let value): service = value
        case .vpn(let value): vpnResource = value
        case .systemEntry(let value): systemEntry = value
        }
    }

    /// 持久化图最终校验此值必须为一。
    var ownerCount: Int { [server, service, vpnResource, systemEntry].compactMap { $0 }.count }
    var project: ProjectRecord? { server?.environment?.project ?? service?.server?.environment?.project ?? vpnResource?.project ?? systemEntry?.project }
}

/// 字段唯一所有者；公开构造不能产生零或多个 owner。
enum FieldOwner {
    case server(ServerRecord)
    case service(ServiceRecord)
    case credentialSet(CredentialSetRecord)
}

/// 字段拥有一个服务器、服务或凭据集，且提交前必须恰有一个 owner。
@Model
final class FieldRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    private(set) var server: ServerRecord?
    private(set) var service: ServiceRecord?
    private(set) var credentialSet: CredentialSetRecord?
    @Relationship(deleteRule: .cascade, inverse: \FieldVersionRecord.field) var versions: [FieldVersionRecord] = []

    init(name: String, owner: FieldOwner) {
        id = UUID()
        self.name = name
        switch owner {
        case .server(let value): server = value
        case .service(let value): service = value
        case .credentialSet(let value): credentialSet = value
        }
    }

    var ownerCount: Int { [server, service, credentialSet].compactMap { $0 }.count }
    var project: ProjectRecord? { server?.environment?.project ?? service?.server?.environment?.project ?? credentialSet?.project }
}

/// 已提交字段版本；field 与片段在持久化图中必须存在，提交后不可重绑定。
@Model
final class FieldVersionRecord {
    @Attribute(.unique) var id: UUID
    var sequence: Int
    var value: String
    var createdAt: Date
    private(set) var field: FieldRecord
    @Relationship(deleteRule: .cascade, inverse: \SourceFragmentRecord.version) private(set) var sourceFragment: SourceFragmentRecord
    @Relationship(inverse: \ChangeSetRecord.versionReferences) var changeSets: [ChangeSetRecord] = []

    fileprivate init(sequence: Int, value: String, field: FieldRecord, sourceFragment: SourceFragmentRecord, createdAt: Date = .now) {
        id = UUID()
        self.sequence = sequence
        self.value = value
        self.field = field
        self.sourceFragment = sourceFragment
        self.createdAt = createdAt
    }
}

/// 字段级最小来源片段，只能通过版本对工厂创建。
@Model
final class SourceFragmentRecord {
    @Attribute(.unique) var id: UUID
    var content: String
    fileprivate(set) var version: FieldVersionRecord?
    @Relationship(inverse: \ChangeSetRecord.fragmentReferences) var changeSets: [ChangeSetRecord] = []

    fileprivate init(content: String) {
        id = UUID()
        self.content = content
    }
}

/// 版本与来源片段的唯一受控创建点，关系只从 FieldVersion 一侧赋值。
enum FieldVersionPairFactory {
    static func make(sequence: Int, value: String, field: FieldRecord, fragmentContent: String) -> (FieldVersionRecord, SourceFragmentRecord) {
        let fragment = SourceFragmentRecord(content: fragmentContent)
        let version = FieldVersionRecord(sequence: sequence, value: value, field: field, sourceFragment: fragment)
        return (version, fragment)
    }
}

/// 变更审计只保存项目、操作、解释、数量和对象引用。
@Model
final class ChangeSetRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var operation: String
    var ruleExplanation: String
    var affectedFieldCount: Int
    var project: ProjectRecord?
    @Relationship(inverse: \FieldVersionRecord.changeSets) var versionReferences: [FieldVersionRecord] = []
    @Relationship(inverse: \SourceFragmentRecord.changeSets) var fragmentReferences: [SourceFragmentRecord] = []

    init(project: ProjectRecord, operation: String, ruleExplanation: String, affectedFieldCount: Int, createdAt: Date = .now) {
        id = UUID()
        self.project = project
        self.operation = operation
        self.ruleExplanation = ruleExplanation
        self.affectedFieldCount = affectedFieldCount
        self.createdAt = createdAt
    }
}

/// 待整理项只保存一份当前原文，不保留历史。
@Model
final class PendingItemRecord {
    @Attribute(.unique) var id: UUID
    var currentRawText: String
    var createdAt: Date
    var project: ProjectRecord?

    init(currentRawText: String, project: ProjectRecord, createdAt: Date = .now) {
        id = UUID()
        self.currentRawText = currentRawText
        self.project = project
        self.createdAt = createdAt
    }
}

/// 整库备份元数据，不绑定单个项目或承载备份导入导出内容。
@Model
final class BackupMetadataRecord {
    @Attribute(.unique) var id: UUID
    var formatVersion: Int
    var checksum: String
    var createdAt: Date

    init(formatVersion: Int, checksum: String, createdAt: Date = .now) {
        id = UUID()
        self.formatVersion = formatVersion
        self.checksum = checksum
        self.createdAt = createdAt
    }
}
