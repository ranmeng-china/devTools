import SwiftData

enum ApplicationPersistence {
    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for:
                ProjectRecord.self,
                EnvironmentRecord.self,
                ServerRecord.self,
                ServerPortRecord.self,
                ServiceRecord.self,
                VPNResourceRecord.self,
                SystemEntryRecord.self,
                CredentialSetRecord.self,
                FieldRecord.self,
                FieldVersionRecord.self,
                SourceFragmentRecord.self,
                ChangeSetRecord.self,
                PendingItemRecord.self,
                BackupMetadataRecord.self
            )
        } catch {
            preconditionFailure("无法初始化本地数据存储。")
        }
    }
}
