package com.termirust.mobile.data

import java.nio.charset.StandardCharsets

object NativeMobileVaultCrypto {
    init {
        System.loadLibrary("termirust_mobile_ffi")
    }

    external fun decryptVaultJson(encryptedVault: ByteArray, passphrase: ByteArray): ByteArray
}

class NativeMobileVaultDecryptor : MobileVaultDecryptor {
    override fun decrypt(encryptedVault: ByteArray, passphrase: CharArray): ByteArray {
        val passphraseBytes = String(passphrase).toByteArray(StandardCharsets.UTF_8)
        return try {
            NativeMobileVaultCrypto.decryptVaultJson(encryptedVault, passphraseBytes)
        } finally {
            passphraseBytes.fill(0)
        }
    }
}
