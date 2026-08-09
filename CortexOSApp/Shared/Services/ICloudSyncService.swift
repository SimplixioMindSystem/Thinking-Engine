//
//  ICloudSyncService.swift
//  CortexOS
//
//  End-to-end encrypted cross-device synchronization using iCloud Keychain
//  for key delivery and iCloud key-value storage for the ciphertext. No
//  SimpliXio or third-party server receives readable user state.
//

import CryptoKit
import Foundation
import Security

enum ICloudSyncState: Equatable {
    case disabled
    case synced
    case localOnly
    case waitingForKey
    case storageFull
    case failed(String)
}

struct ICloudSyncResult: Equatable {
    let state: ICloudSyncState
    let updatedAt: Date
    let payloadBytes: Int

    var userMessage: String {
        switch state {
        case .disabled:
            return "On this device"
        case .synced:
            return "Encrypted iCloud sync active"
        case .localOnly:
            return "Saved locally - iCloud will retry"
        case .waitingForKey:
            return "Saved locally - waiting for private sync key"
        case .storageFull:
            return "iCloud sync storage is full"
        case .failed:
            return "Saved locally - iCloud unavailable"
        }
    }
}

enum ICloudSyncCodec {
    private static let encryptedHeader = Data("SXE1".utf8)
    private static let legacyHeader = Data("SXC1".utf8)

    static func encode(_ payload: PrivateSyncPayload, key: SymmetricKey) throws -> Data {
        let raw = try JSONEncoder().encode(payload)
        let compressed = try (raw as NSData).compressed(using: .lzfse) as Data
        let sealed = try AES.GCM.seal(compressed, using: key)
        guard let combined = sealed.combined else {
            throw ICloudSyncError.encryptionFailed
        }
        return encryptedHeader + combined
    }

    static func decode(_ data: Data, key: SymmetricKey) throws -> PrivateSyncPayload {
        guard data.starts(with: encryptedHeader) else {
            throw ICloudSyncError.invalidPayload
        }
        let sealed = try AES.GCM.SealedBox(combined: data.dropFirst(encryptedHeader.count))
        let compressed = try AES.GCM.open(sealed, using: key)
        let raw = try (compressed as NSData).decompressed(using: .lzfse) as Data
        return try validatedPayload(from: raw)
    }

    static func isEncrypted(_ data: Data) -> Bool {
        data.starts(with: encryptedHeader)
    }

    static func hasSameContent(_ lhs: PrivateSyncPayload, _ rhs: PrivateSyncPayload) throws -> Bool {
        var normalizedLeft = lhs
        normalizedLeft.modifiedAt = ""
        normalizedLeft.deviceID = ""
        normalizedLeft.notes.sort { $0.id < $1.id }
        normalizedLeft.decisions.sort { $0.id < $1.id }
        normalizedLeft.insights.sort { $0.id < $1.id }
        normalizedLeft.feedback.sort { $0.id < $1.id }

        var normalizedRight = rhs
        normalizedRight.modifiedAt = ""
        normalizedRight.deviceID = ""
        normalizedRight.notes.sort { $0.id < $1.id }
        normalizedRight.decisions.sort { $0.id < $1.id }
        normalizedRight.insights.sort { $0.id < $1.id }
        normalizedRight.feedback.sort { $0.id < $1.id }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(normalizedLeft) == encoder.encode(normalizedRight)
    }

    static func decodeLegacy(_ data: Data) throws -> PrivateSyncPayload {
        guard data.starts(with: legacyHeader) else {
            throw ICloudSyncError.invalidPayload
        }
        let compressed = data.dropFirst(legacyHeader.count)
        let raw = try (Data(compressed) as NSData).decompressed(using: .lzfse) as Data
        return try validatedPayload(from: raw)
    }

    private static func validatedPayload(from data: Data) throws -> PrivateSyncPayload {
        let payload = try JSONDecoder().decode(PrivateSyncPayload.self, from: data)
        guard payload.schemaVersion <= PrivateSyncPayload.currentSchemaVersion else {
            throw ICloudSyncError.unsupportedSchema(payload.schemaVersion)
        }
        return payload
    }
}

private enum ICloudSyncError: LocalizedError {
    case encryptionFailed
    case invalidPayload
    case keychain(OSStatus)
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "Private sync encryption failed."
        case .invalidPayload:
            return "Private sync data could not be verified."
        case .keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            return "Private sync key is unavailable (\(detail))."
        case .unsupportedSchema(let version):
            return "Private sync data uses schema \(version). Update SimpliXio before syncing this device."
        }
    }
}

private struct ICloudEncryptionKeyStore {
    private let service = "me.ph7.cortexos.private-sync"
    private let account = "payload-key-v1"
    private let accessGroup: String

    init(accessGroup: String) {
        self.accessGroup = accessGroup
    }

    func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == 32 else {
                throw ICloudSyncError.invalidPayload
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw ICloudSyncError.keychain(status)
        }
    }

    func create() throws -> Data {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return data
        case errSecDuplicateItem:
            guard let existing = try load() else {
                throw ICloudSyncError.keychain(status)
            }
            return existing
        default:
            throw ICloudSyncError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        ]
    }
}

actor ICloudSyncService {
    static let shared = ICloudSyncService()

    static let enabledDefaultsKey = "simplixio_icloud_sync_enabled"
    static let externalChangeNotification = NSUbiquitousKeyValueStore.didChangeExternallyNotification

    private let payloadKey = "simplixio.private-state.encrypted.v1"
    private let keyFingerprintKey = "simplixio.private-state.key-fingerprint.v1"
    private let modifiedAtKey = "simplixio.private-state.modified-at.v1"
    private let deviceIDKey = "simplixio_private_sync_device_id"
    private let maximumPayloadBytes = 900_000

    private let cloudStore: NSUbiquitousKeyValueStore?
    private let defaults: UserDefaults
    private let keyStore: ICloudEncryptionKeyStore?

    init(
        cloudStore: NSUbiquitousKeyValueStore? = nil,
        defaults: UserDefaults = .standard
    ) {
        if let cloudStore {
            self.cloudStore = cloudStore
        } else if Self.hasCloudStoreEntitlement {
            self.cloudStore = .default
        } else {
            // A missing or invalid signing entitlement must never prevent the
            // local-first app from opening. Release builds include this
            // entitlement; previews and ad-hoc builds safely stay local.
            self.cloudStore = nil
        }
        self.keyStore = Self.sharedKeychainAccessGroup.map(ICloudEncryptionKeyStore.init)
        self.defaults = defaults
    }

    var isEnabled: Bool {
        if defaults.object(forKey: Self.enabledDefaultsKey) == nil {
            defaults.set(true, forKey: Self.enabledDefaultsKey)
        }
        return defaults.bool(forKey: Self.enabledDefaultsKey)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledDefaultsKey)
    }

    func synchronize(store: OfflineStore = .shared) async -> ICloudSyncResult {
        guard isEnabled else {
            return result(.disabled)
        }

        guard let cloudStore, let keyStore else {
            return result(.localOnly)
        }

        // KVS maintains a local cache and propagates changes automatically.
        // Calling synchronize() can block for a long time when iCloud is
        // unavailable, making otherwise-local UI interactions appear frozen.
        let remoteData = cloudStore.data(forKey: payloadKey)
        let remoteFingerprint = cloudStore.string(forKey: keyFingerprintKey)

        do {
            var keyData = try keyStore.load()
            if keyData == nil {
                // Never create a competing key when encrypted state already
                // exists. iCloud Keychain can arrive after the data payload.
                if remoteData?.isEmpty == false || remoteFingerprint?.isEmpty == false {
                    return result(.waitingForKey)
                }
                keyData = try keyStore.create()
            }

            guard let keyData else {
                return result(.waitingForKey)
            }

            let fingerprint = Self.fingerprint(for: keyData)
            if let remoteFingerprint,
               !remoteFingerprint.isEmpty,
               remoteFingerprint != fingerprint {
                return result(.waitingForKey)
            }

            let key = SymmetricKey(data: keyData)
            let local = await store.privateSyncPayload(deviceID: deviceID)
            let merged: PrivateSyncPayload

            if let remoteData, !remoteData.isEmpty {
                let remote: PrivateSyncPayload
                let remoteWasEncrypted = ICloudSyncCodec.isEncrypted(remoteData)
                if remoteWasEncrypted {
                    do {
                        remote = try ICloudSyncCodec.decode(remoteData, key: key)
                    } catch let error as ICloudSyncError {
                        if case .unsupportedSchema = error {
                            return result(.failed(error.localizedDescription), payloadBytes: remoteData.count)
                        }
                        // Authentication failure usually means the matching
                        // keychain item has not reconciled yet. Preserve both
                        // local and cloud data by refusing to overwrite.
                        return result(.waitingForKey, payloadBytes: remoteData.count)
                    } catch {
                        // CryptoKit and decompression errors are also treated as
                        // a non-destructive key reconciliation delay.
                        return result(.waitingForKey, payloadBytes: remoteData.count)
                    }
                } else {
                    // Migrate the development-only plaintext format once, then
                    // replace it immediately with authenticated ciphertext.
                    remote = try ICloudSyncCodec.decodeLegacy(remoteData)
                }
                merged = await store.mergePrivateSyncPayload(remote, deviceID: deviceID)

                // External KVS notifications can arrive on every participating
                // device. Avoid rewriting identical ciphertext with a fresh
                // timestamp, which would otherwise create needless sync churn.
                if remoteWasEncrypted,
                   try ICloudSyncCodec.hasSameContent(remote, merged) {
                    if remoteFingerprint?.isEmpty != false {
                        cloudStore.set(fingerprint, forKey: keyFingerprintKey)
                    }
                    return result(
                        FileManager.default.ubiquityIdentityToken == nil ? .localOnly : .synced,
                        payloadBytes: remoteData.count
                    )
                }
            } else {
                merged = local
            }

            let encoded = try ICloudSyncCodec.encode(merged, key: key)
            guard encoded.count <= maximumPayloadBytes else {
                return result(.storageFull, payloadBytes: encoded.count)
            }

            cloudStore.set(encoded, forKey: payloadKey)
            cloudStore.set(fingerprint, forKey: keyFingerprintKey)
            cloudStore.set(merged.modifiedAt, forKey: modifiedAtKey)
            return result(
                FileManager.default.ubiquityIdentityToken == nil ? .localOnly : .synced,
                payloadBytes: encoded.count
            )
        } catch {
            return result(.failed(error.localizedDescription))
        }
    }

    private func result(
        _ state: ICloudSyncState,
        payloadBytes: Int = 0
    ) -> ICloudSyncResult {
        ICloudSyncResult(state: state, updatedAt: Date(), payloadBytes: payloadBytes)
    }

    private static func fingerprint(for keyData: Data) -> String {
        Data(SHA256.hash(data: keyData).prefix(12)).base64EncodedString()
    }

    private static var hasCloudStoreEntitlement: Bool {
        #if targetEnvironment(simulator)
        // Simulator builds are intentionally local-only. Device and App Store
        // builds receive the real iCloud entitlement through signing.
        return false
        #elseif os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.developer.ubiquity-kvstore-identifier" as CFString,
                  nil
              ) as? String else {
            return false
        }
        return !value.isEmpty
        #else
        return true
        #endif
    }

    private static var sharedKeychainAccessGroup: String? {
        guard let group = Bundle.main.object(
            forInfoDictionaryKey: "SimpliXioKeychainAccessGroup"
        ) as? String,
              !group.contains("$("),
              group.hasSuffix(".me.ph7.cortexos.shared") else {
            return nil
        }
        return group
    }

    private var deviceID: String {
        if let existing = defaults.string(forKey: deviceIDKey), !existing.isEmpty {
            return existing
        }
        let value = UUID().uuidString
        defaults.set(value, forKey: deviceIDKey)
        return value
    }
}
