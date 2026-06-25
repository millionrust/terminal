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
- `NativeMobileVaultDecryptor` Swift adapter for the Rust shared crypto XCFramework.
- Keychain wrapper using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Tmux bootstrap script generation.
- SwiftNIO SSH dependency is linked as the direct SSH transport foundation.
- Unit tests for schema decode and tmux bootstrap behavior.

Not finished yet:

- Shipping the generated Rust XCFramework with release builds. The app target expects it at `../../terminal/dist/mobile/ios/TermiRustMobileCrypto.xcframework` relative to this folder.
- Full SwiftNIO SSH session/channel wiring.
- Real terminal emulator integration. SwiftTerm is the right candidate, but this Xcode install is missing the Metal Toolchain needed to build SwiftTerm. Re-enable SwiftTerm after installing it with `xcodebuild -downloadComponent MetalToolchain` or through Xcode Settings > Components.

## Build

```bash
cd /Users/jacob/Projects/terminal
scripts/build-mobile-ffi-ios.sh

cd /Users/jacob/Projects/terminal_app/terminal_swift
xcodegen generate
xcodebuild test -project TermiRustMobile.xcodeproj -scheme TermiRustMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
