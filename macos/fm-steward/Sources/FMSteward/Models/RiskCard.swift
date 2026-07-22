import Foundation

/// Risk card request matching `Schemas/risk-card-v1.json`.
public struct RiskCard: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var sessionId: String
    public var tool: String
    public var command: String?
    public var features: Features
    public var thresholds: Thresholds?
    public var meta: Meta?

    public init(
        schemaVersion: Int = 1,
        sessionId: String,
        tool: String,
        command: String? = nil,
        features: Features,
        thresholds: Thresholds? = nil,
        meta: Meta? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sessionId = sessionId
        self.tool = tool
        self.command = command
        self.features = features
        self.thresholds = thresholds
        self.meta = meta
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionId = "session_id"
        case tool
        case command
        case features
        case thresholds
        case meta
    }

    /// Default bulk recipient threshold when `thresholds.bulk_recipient_min` is omitted.
    public static let defaultBulkRecipientMin: Int = 1000

    /// Effective bulk recipient threshold (clamped; absurd caller overrides → default).
    public var bulkRecipientMin: Int {
        RulesPrePass.clampBulkRecipientMin(thresholds?.bulkRecipientMin)
    }

    public struct Features: Codable, Sendable, Equatable {
        public var executed: Bool?
        public var bulkOutbound: Bool?
        public var vip: Bool?
        public var sameIntent: String?
        public var recipientCount: Int?
        public var recipientClass: String?
        public var amount: Double?
        public var currency: String?
        public var paths: [String]?
        public var effectHints: [String]?
        public var packId: String?
        public var namespace: String?
        public var ruleId: String?

        public init(
            executed: Bool? = nil,
            bulkOutbound: Bool? = nil,
            vip: Bool? = nil,
            sameIntent: String? = nil,
            recipientCount: Int? = nil,
            recipientClass: String? = nil,
            amount: Double? = nil,
            currency: String? = nil,
            paths: [String]? = nil,
            effectHints: [String]? = nil,
            packId: String? = nil,
            namespace: String? = nil,
            ruleId: String? = nil
        ) {
            self.executed = executed
            self.bulkOutbound = bulkOutbound
            self.vip = vip
            self.sameIntent = sameIntent
            self.recipientCount = recipientCount
            self.recipientClass = recipientClass
            self.amount = amount
            self.currency = currency
            self.paths = paths
            self.effectHints = effectHints
            self.packId = packId
            self.namespace = namespace
            self.ruleId = ruleId
        }

        enum CodingKeys: String, CodingKey {
            case executed
            case bulkOutbound = "bulk_outbound"
            case vip
            case sameIntent = "same_intent"
            case recipientCount = "recipient_count"
            case recipientClass = "recipient_class"
            case amount
            case currency
            case paths
            case effectHints = "effect_hints"
            case packId = "pack_id"
            case namespace
            case ruleId = "rule_id"
        }
    }

    public struct Thresholds: Codable, Sendable, Equatable {
        public var bulkRecipientMin: Int?
        public var vipListPath: String?

        public init(bulkRecipientMin: Int? = nil, vipListPath: String? = nil) {
            self.bulkRecipientMin = bulkRecipientMin
            self.vipListPath = vipListPath
        }

        enum CodingKeys: String, CodingKey {
            case bulkRecipientMin = "bulk_recipient_min"
            case vipListPath = "vip_list_path"
        }
    }

    public struct Meta: Codable, Sendable, Equatable {
        public var host: String?
        public var cwd: String?

        public init(host: String? = nil, cwd: String? = nil) {
            self.host = host
            self.cwd = cwd
        }
    }
}
