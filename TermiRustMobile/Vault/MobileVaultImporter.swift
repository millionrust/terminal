import Foundation

enum MobileVaultImportError: Error, LocalizedError {
    case unsupportedSchema(Int)
    case encryptedVaultRequiresSharedCrypto
    case invalidVault

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "Unsupported mobile vault schema version \(version)."
        case .encryptedVaultRequiresSharedCrypto:
            return "This encrypted vault uses TermiRust shared crypto. Link the shared Rust vault crypto before importing encrypted production vaults."
        case .invalidVault:
            return "The selected file is not a valid TermiRust mobile vault."
        }
    }
}

struct MobileVaultImporter {
    private let decoder = JSONDecoder()

    func inspectEncryptedEnvelope(_ data: Data) throws -> EncryptedMobileVaultEnvelope {
        let envelope = try decoder.decode(EncryptedMobileVaultEnvelope.self, from: data)
        guard envelope.schemaVersion == mobileVaultSchemaVersion else {
            throw MobileVaultImportError.unsupportedSchema(envelope.schemaVersion)
        }
        return envelope
    }

    func importPlaintextVaultData(_ data: Data) throws -> MobileVaultExport {
        let vault = try decoder.decode(MobileVaultExport.self, from: data)
        guard vault.schemaVersion == mobileVaultSchemaVersion else {
            throw MobileVaultImportError.unsupportedSchema(vault.schemaVersion)
        }
        return vault
    }

    func importEncryptedVaultData(_ data: Data, passphrase: String) throws -> MobileVaultExport {
        _ = try inspectEncryptedEnvelope(data)
        _ = passphrase
        throw MobileVaultImportError.encryptedVaultRequiresSharedCrypto
    }
}
