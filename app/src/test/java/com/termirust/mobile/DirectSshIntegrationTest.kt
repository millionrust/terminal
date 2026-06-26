package com.termirust.mobile

import com.termirust.mobile.data.MobileAuthKind
import com.termirust.mobile.data.MobileAuthMetadata
import com.termirust.mobile.data.MobileHost
import com.termirust.mobile.data.MobileKnownHost
import com.termirust.mobile.data.MobilePersistentSession
import com.termirust.mobile.ssh.DirectSshSessionClient
import com.termirust.mobile.ssh.MobileSshSecretProvider
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList

class DirectSshIntegrationTest {
    @Test
    fun directSshAttachesToPersistentTmuxSessionAndSurvivesReconnect() = runBlocking {
        val hostName = env("TERMIRUST_MOBILE_TEST_SSH_HOST")
        val port = env("TERMIRUST_MOBILE_TEST_SSH_PORT").toIntOrNull()
        val username = env("TERMIRUST_MOBILE_TEST_SSH_USER")
        val privateKey = env("TERMIRUST_MOBILE_TEST_SSH_KEY")
        val knownHostKey = env("TERMIRUST_MOBILE_TEST_KNOWN_HOST_KEY")
        assumeTrue(
            "Set TERMIRUST_MOBILE_TEST_SSH_HOST, TERMIRUST_MOBILE_TEST_SSH_PORT, TERMIRUST_MOBILE_TEST_SSH_USER, TERMIRUST_MOBILE_TEST_SSH_KEY, and TERMIRUST_MOBILE_TEST_KNOWN_HOST_KEY to run this live SSH smoke.",
            hostName.isNotBlank() &&
                port != null &&
                username.isNotBlank() &&
                privateKey.isNotBlank() &&
                knownHostKey.isNotBlank(),
        )

        val sessionName = "mobile-android-smoke"
        val secretRef = "termirust-mobile-test-private-key"
        val host = MobileHost(
            id = "android-live-ssh",
            label = "Android Live SSH",
            host = hostName,
            port = port!!,
            username = username,
            auth = MobileAuthMetadata(
                kind = MobileAuthKind.PrivateKey,
                secretRef = secretRef,
            ),
            persistentSession = MobilePersistentSession(
                enabled = true,
                sessionName = sessionName,
                detachOthers = false,
            ),
            knownHostEndpoint = "$hostName:$port",
        )
        val knownHost = MobileKnownHost(
            endpoint = "$hostName:$port",
            publicKey = knownHostKey,
        )

        val firstOutput = CopyOnWriteArrayList<ByteArray>()
        val firstClient = clientWithKey(secretRef, privateKey)
        try {
            firstClient.connect(host, knownHost) { firstOutput += it.copyOf() }
            firstClient.send("tmux display-message -p '#S'\n".encodeToByteArray())
            firstClient.send("echo android-smoke-first > ~/termirust-android-smoke\n".encodeToByteArray())

            assertTrue(
                "first connection did not attach to the expected tmux session",
                waitForOutput(firstOutput, sessionName),
            )
        } finally {
            firstClient.disconnect()
            firstClient.close()
        }

        val secondOutput = CopyOnWriteArrayList<ByteArray>()
        val secondClient = clientWithKey(secretRef, privateKey)
        try {
            secondClient.connect(host, knownHost) { secondOutput += it.copyOf() }
            secondClient.send("cat ~/termirust-android-smoke\n".encodeToByteArray())

            assertTrue(
                "reconnect did not see marker created inside the persistent tmux session",
                waitForOutput(secondOutput, "android-smoke-first"),
            )
        } finally {
            secondClient.disconnect()
            secondClient.close()
        }
    }

    private fun clientWithKey(secretRef: String, privateKey: String): DirectSshSessionClient =
        DirectSshSessionClient(
            secretProvider = MobileSshSecretProvider { reference ->
                if (reference == secretRef) privateKey.toCharArray() else null
            },
        )

    private suspend fun waitForOutput(
        chunks: List<ByteArray>,
        needle: String,
        attempts: Int = 80,
    ): Boolean {
        repeat(attempts) {
            if (chunks.joinToString(separator = "") { it.decodeToString() }.contains(needle)) {
                return true
            }
            delay(250)
        }
        return false
    }

    private fun env(name: String): String =
        System.getenv(name)?.trim().orEmpty()
}
