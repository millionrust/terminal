# TermiRust Mobile Android Prototype

This folder contains the first Android prototype scaffold for TermiRust mobile terminal access.

## Architecture

- Direct SSH to the target host, not a desktop relay.
- Shared mobile vault schema compatible with the desktop mobile export.
- Per-host tmux bootstrap generation so Android attaches to the same named session.
- Android Keystore-backed AES-GCM wrapping for secrets entered on device.
- Known-host pins are required before a connection attempt proceeds.

## Current State

Implemented:

- Jetpack Compose host list and terminal detail scaffold.
- Versioned mobile vault models using kotlinx.serialization.
- Plaintext fixture import for unit tests, encrypted envelope inspection, and an injected shared-crypto decryptor path for production vault files.
- Android Keystore-backed secret storage.
- Tmux bootstrap script generation.
- SSHJ dependency is declared as the direct SSH transport foundation.
- JVM unit tests for schema decode and tmux bootstrap behavior.

Not finished yet:

- Linking the production Rust vault crypto library into the app target. The import path is ready through `MobileVaultDecryptor`; the remaining work is packaging the shared Rust decryptor through JNI/UniFFI.
- Full SSHJ session/channel/PTTY wiring.
- Real terminal emulator integration.
- Android document picker integration for vault import.

## Build

This machine did not have Gradle or the Android SDK command-line tools installed when the scaffold was created. On a normal Android Studio setup:

```bash
./gradlew testDebugUnitTest
./gradlew assembleDebug
```
