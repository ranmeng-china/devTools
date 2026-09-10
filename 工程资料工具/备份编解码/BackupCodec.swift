import Foundation

/// 备份编解码层的独立数据信封；尚未接入真实业务数据。
struct BackupEnvelope: Codable, Equatable {
    let formatVersion: Int
    let createdAt: Date
}

/// 仅处理数据与 JSON 之间的转换，不处理文件选择或用户确认。
struct BackupCodec {
    func encode(_ envelope: BackupEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    func decode(_ data: Data) throws -> BackupEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupEnvelope.self, from: data)
    }
}
