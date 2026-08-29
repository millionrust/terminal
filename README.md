# TermiRust Mobile for Android

This folder contains the unified native TermiRust mobile application.

## Architecture

- **Connections** are saved direct-SSH destinations with device-local SSH credentials,
  mandatory known-host pins, and optional remote-tmux continuity.
- **Devices** are paired TermiRust desktops that list durable Device Sessions. The Host
  service owns replay, authoritative activity, and single-writer coordination.
- Route credentials, capabilities, lifecycle, and continuity remain separate inside one
  application and one APK.

## Current State

Implemented:

- Adaptive Compose shell with a phone navigation bar and tablet navigation rail.
- Permanent Direct SSH and Device Session labels on terminal routes.
- Background privacy covers and pending-input cleanup for both terminal routes.
- Jetpack Compose Connection list and direct terminal detail.
- Versioned mobile vault models using kotlinx.serialization.
- Plaintext fixture import for unit tests, encrypted envelope inspection, and encrypted production vault import through the shared Rust crypto library.
- `NativeMobileVaultDecryptor` JNI adapter with `libtermirust_mobile_ffi.so` packaged for Android ABIs in `app/src/main/jniLibs/`.
- Android document picker flow for encrypted mobile vault import.
- Android Keystore-backed secret storage.
- Selected-host credential entry that saves password/private-key material into Keystore-backed storage under the exported `secret_ref`, including private-key file import.
- Tmux bootstrap script generation.
- SSHJ-backed direct SSH session wiring with pinned known-host verification, Keystore-backed `secret_ref` lookup, PTY shell startup, tmux bootstrap injection, terminal input, resize, and disconnect.
- Transcript-level terminal buffering for common redraw/control sequences such as carriage return, backspace, ANSI SGR, line erase, cursor movement, and clear screen.
- JVM route, terminal, schema, tmux, lifecycle, and Controller protocol tests.

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
./scripts/verify-android-unified-routes.sh
```

If Android Studio installed the SDK somewhere else, replace the `sdk.dir` path
or set `ANDROID_HOME` for the Gradle commands.
