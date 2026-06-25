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
- `NativeMobileVaultDecryptor` JNI adapter for the Rust shared crypto library once `libtermirust_mobile_ffi.so` is copied into `app/src/main/jniLibs/`.
- Android Keystore-backed secret storage.
- Tmux bootstrap script generation.
- SSHJ-backed direct SSH session wiring with pinned known-host verification, Keystore-backed `secret_ref` lookup, PTY shell startup, tmux bootstrap injection, terminal input, resize, and disconnect.
- JVM unit tests for schema decode and tmux bootstrap behavior.

Not finished yet:

- Making `NativeMobileVaultDecryptor` the default import decryptor after the shared Rust `.so` files are shipped with the app.
- UI for entering/importing per-host password or private-key secrets into Android Keystore-backed storage.
- Real terminal emulator integration.
- Android document picker integration for vault import.

## Build

On a normal Android Studio setup, use the project Gradle wrapper once one is generated:

```bash
./gradlew testDebugUnitTest
./gradlew assembleDebug
```

This workspace was also verified with the cached local Gradle distribution:

```bash
ANDROID_HOME=/Users/jacob/Library/Android/sdk \
ANDROID_SDK_ROOT=/Users/jacob/Library/Android/sdk \
/Users/jacob/.gradle/wrapper/dists/gradle-8.13-bin/5xuhj0ry160q40clulazy9h7d/gradle-8.13/bin/gradle testDebugUnitTest --no-daemon

ANDROID_HOME=/Users/jacob/Library/Android/sdk \
ANDROID_SDK_ROOT=/Users/jacob/Library/Android/sdk \
/Users/jacob/.gradle/wrapper/dists/gradle-8.13-bin/5xuhj0ry160q40clulazy9h7d/gradle-8.13/bin/gradle assembleDebug --no-daemon
```
