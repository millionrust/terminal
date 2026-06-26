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
- Plaintext fixture import for unit tests, encrypted envelope inspection, and encrypted production vault import through the shared Rust crypto library.
- `NativeMobileVaultDecryptor` JNI adapter with `libtermirust_mobile_ffi.so` packaged for Android ABIs in `app/src/main/jniLibs/`.
- Android document picker flow for encrypted mobile vault import.
- Android Keystore-backed secret storage.
- Selected-host credential entry that saves password/private-key material into Keystore-backed storage under the exported `secret_ref`, including private-key file import.
- Tmux bootstrap script generation.
- SSHJ-backed direct SSH session wiring with pinned known-host verification, Keystore-backed `secret_ref` lookup, PTY shell startup, tmux bootstrap injection, terminal input, resize, and disconnect.
- Transcript-level terminal buffering for common redraw/control sequences such as carriage return, backspace, ANSI SGR, line erase, cursor movement, and clear screen.
- JVM unit tests for schema decode and tmux bootstrap behavior.

Not finished yet:

- Full terminal emulator integration with complete VT parsing, styling, selection, and alternate screen support.

## Build

Refresh the shared Rust mobile crypto JNI libraries when the desktop FFI crate changes:

```bash
cd /Users/jacob/Projects/terminal
scripts/sync-mobile-ffi-artifacts.sh android
```

Use the checked-in Gradle wrapper:

```bash
echo "sdk.dir=/Users/jacob/Library/Android/sdk" > local.properties
./gradlew testDebugUnitTest
./gradlew assembleDebug
```

If Android Studio installed the SDK somewhere else, replace the `sdk.dir` path
or set `ANDROID_HOME` for the Gradle commands.
