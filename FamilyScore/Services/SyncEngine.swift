import Foundation
import SwiftData
import CloudKit

// MARK: - ChangeLog（本地变更队列，§18.3 离线队列）

@Model
final class ChangeLog {
    @Attribute(.unique) var id: UUID
    var familyID: UUID
    var entityName: String    // Member/ScoreRecord/Rule/...（避开 NSManagedObject.entity 保留名）
    var entityID: UUID
    var operation: String     // create / update / delete / redeem / approve / reverse / config
    var deviceID: String
    var changedAt: Date
    var syncedAt: Date?       // 已推送到云的时间；nil = 待同步

    init(familyID: UUID, entityName: String, entityID: UUID, operation: String,
         deviceID: String, changedAt: Date = .now) {
        self.id = UUID()
        self.familyID = familyID
        self.entityName = entityName
        self.entityID = entityID
        self.operation = operation
        self.deviceID = deviceID
        self.changedAt = changedAt
        self.syncedAt = nil
    }
}

// MARK: - 同步引擎（§18.3：append-only 增量幂等合并，配置类本地优先 + 冲突报告）

enum SyncEngine {

    static var deviceID: String {
        let key = "fs.sync.deviceID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = "dev-" + UUID().uuidString.prefix(8)
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    /// 记账（由 AuditService.log 全埋点调用——所有关键操作都过审计，一处覆盖全部变更）
    static func record(familyID: UUID, action: AuditAction, targetID: UUID, context: ModelContext) {
        let entity: String
        switch action {
        case .add, .deduct, .approve, .reject, .reverse: entity = "ScoreRecord"
        case .redeem: entity = "Redemption"
        case .config: entity = "Family"
        }
        context.insert(ChangeLog(familyID: familyID, entityName: entity, entityID: targetID,
                                 operation: action.rawValue, deviceID: deviceID))
    }

    static func unsynced(context: ModelContext) -> [ChangeLog] {
        (try? context.fetch(FetchDescriptor<ChangeLog>(
            predicate: #Predicate { $0.syncedAt == nil }))) ?? []
    }

    static func markAllSynced(context: ModelContext) {
        for c in unsynced(context: context) { c.syncedAt = .now }
        try? context.save()
    }

    // MARK: 变更信封（跨设备交换单元）

    struct Envelope: Codable, Equatable {
        var entity: String
        var entityID: UUID
        var deviceID: String
        var changedAt: Date
        var operation: String
    }

    /// 冲突检测（纯函数）：同实体多设备并行修改 → 冲突列表（供审计提示，不自动裁决）
    static func conflicts(in envelopes: [Envelope]) -> [(entityID: UUID, devices: [String])] {
        var byEntity: [UUID: [Envelope]] = [:]
        for e in envelopes { byEntity[e.entityID, default: []].append(e) }
        return byEntity.compactMap { id, list in
            let devices = Set(list.map(\.deviceID))
            return devices.count > 1 ? (id, Array(devices).sorted()) : nil
        }
    }

    /// 应用远端数据包：复用导出导入的 UUID 幂等合并（本地已存在则跳过 = 本地优先）
    static func applyRemote(_ bundle: ExportService.ExportBundle,
                            context: ModelContext) throws -> ExportService.ImportReport {
        try ExportService.import(bundle, context: context)
    }
}

// MARK: - CloudKit 传输层（§18.3）
// 云端模型：CKRecord(recordType: "FamilyBundle", recordID: familyID) 的 "payload" 字段存导出 JSON。
// 家庭共享用 CKShare 包装该 record，成员设备经 share 参与同步。无 iCloud 账号 → 本地模式（功能不中断）。

enum CloudSyncStatus: Equatable {
    case localOnly          // 无账号/未配置：纯本地
    case available          // iCloud 可用
    case syncing
    case lastSynced(Date)
    case failed(String)
}

enum CloudSyncService {

    static func checkStatus(_ completion: @escaping (CloudSyncStatus) -> Void) {
        CKContainer.default().accountStatus { status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    completion(.available)
                case .noAccount, .restricted, .couldNotDetermine, .temporarilyUnavailable:
                    completion(.localOnly)
                @unknown default:
                    completion(.localOnly)
                }
                if let error { completion(.failed(error.localizedDescription)) }
            }
        }
    }

    /// 推送：导出全量 bundle → CKRecord payload（真实推送需要 entitlements + 账号；本地调用返回 false 表示未执行）
    static func push(family: Family, context: ModelContext) -> Bool {
        guard let bundle = try? ExportService.export(family: family, context: context),
              let payload = try? ExportService.encode(bundle) else { return false }
        let record = CKRecord(recordType: "FamilyBundle", recordID: CKRecord.ID(recordName: family.id.uuidString))
        record["payload"] = payload as CKRecordValue
        record["familyName"] = family.name as CKRecordValue
        record["updatedAt"] = Date.now as CKRecordValue
        // 上传：CKContainer.default().database(with: .privateDB).save(record)
        // 当前构建（无 iCloud entitlement/账号）保留本地记账，返回 false 由 UI 呈现"本地模式"
        _ = record
        return false
    }

    /// 拉取并合并远端 bundle（真实环境从 CKQuery/zone 变更取 payload → SyncEngine.applyRemote）
    static func pullAndMerge(familyID: UUID, payload: Data?, context: ModelContext) -> Bool {
        guard let payload,
              let bundle = try? ExportService.decode(payload) else { return false }
        _ = try? SyncEngine.applyRemote(bundle, context: context)
        return true
    }
}
