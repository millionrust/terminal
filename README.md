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
- Plaintext fixture import for tests and encrypted envelope inspection for production vault files.
- Keychain wrapper using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Tmux bootstrap script generation.
- SwiftNIO SSH dependency is linked as the direct SSH transport foundation.
- Unit tests for schema decode and tmux bootstrap behavior.

Not finished yet:

- Production encrypted vault decryption. The desktop export currently uses AES-256-GCM-SIV plus Argon2id, so the mobile app should share the Rust vault crypto via FFI instead of reimplementing crypto separately in Swift.
- Full SwiftNIO SSH session/channel wiring.
- Real terminal emulator integration. SwiftTerm is the right candidate, but this Xcode install is missing the Metal Toolchain needed to build SwiftTerm. Re-enable SwiftTerm after installing it with `xcodebuild -downloadComponent MetalToolchain` or through Xcode Settings > Components.

## Build

```bash
xcodegen generate
xcodebuild test -project TermiRustMobile.xcodeproj -scheme TermiRustMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
