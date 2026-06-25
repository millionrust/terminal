# TermiRust Mobile iOS Prototype

This folder contains the first iOS prototype for TermiRust mobile terminal access.

## Architecture

- Direct SSH to the target host, not a desktop relay.
- Shared mobile vault schema compatible with the desktop mobile export.
- Per-host tmux bootstrap generation so mobile attaches to the same named session.
- Keychain-backed secret storage for credentials that are entered on device.
- Known-host pins are required before a connection attempt proceeds.

## Current State

Implemented:

- SwiftUI shell with host list, import entry point, terminal detail view, and keyboard accessory row.
- Versioned mobile vault models.
- Plaintext fixture import for tests, encrypted envelope inspection, and an injected shared-crypto decryptor path for production vault files.
- Keychain wrapper using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Tmux bootstrap script generation.
- SwiftNIO SSH dependency is linked as the direct SSH transport foundation.
- Unit tests for schema decode and tmux bootstrap behavior.

Not finished yet:

- Linking the production Rust vault crypto library into the app target. The import path is ready through `MobileVaultDecrypting`; the remaining work is packaging the shared Rust decryptor as an iOS binary/FFI module.
- Full SwiftNIO SSH session/channel wiring.
- Real terminal emulator integration. SwiftTerm is the right candidate, but this Xcode install is missing the Metal Toolchain needed to build SwiftTerm. Re-enable SwiftTerm after installing it with `xcodebuild -downloadComponent MetalToolchain` or through Xcode Settings > Components.

## Build

```bash
xcodegen generate
xcodebuild test -project TermiRustMobile.xcodeproj -scheme TermiRustMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
