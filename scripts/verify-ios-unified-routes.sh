#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUIRE_RUNTIME="${REQUIRE_IOS_RUNTIME:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-runtime)
      REQUIRE_RUNTIME=1
      shift
      ;;
    --configuration)
      [[ $# -ge 2 ]] || { printf 'Missing configuration value.\n' >&2; exit 2; }
      shift 2
      ;;
    *)
      printf 'Usage: %s [--require-runtime]\n' "$0" >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

command -v xcodegen >/dev/null || { printf 'xcodegen is required.\n' >&2; exit 1; }
[[ -d Frameworks/TermiRustMobileCrypto.xcframework ]] || {
  printf 'Direct SSH crypto XCFramework is missing.\n' >&2
  exit 1
}
[[ -d Frameworks/TermiRustControllerSecurity.xcframework ]] || {
  printf 'Controller security XCFramework is missing.\n' >&2
  exit 1
}

required_sources=(
  TermiRustMobile/SSH/MobileSSHSession.swift
  TermiRustMobile/SSH/TmuxBootstrap.swift
  TermiRustMobile/ViewModels/HostListViewModel.swift
  TermiRustMobile/Views/ContentView.swift
  TermiRustMobile/Views/ControllerRootView.swift
)
for path in "${required_sources[@]}"; do
  [[ -f "$path" ]] || { printf 'Unified route source is missing: %s\n' "$path" >&2; exit 1; }
done

grep -Eq '^[[:space:]]+UNIFIED_MOBILE_ROUTES:[[:space:]]+1$' project.yml || {
  printf 'The product target must enable unified mobile routes.\n' >&2
  exit 1
}
grep -Eq 'ContentView\(viewModel: connectionViewModel\)' TermiRustMobile/App/TermiRustMobileApp.swift || {
  printf 'Unified navigation does not expose saved Connections.\n' >&2
  exit 1
}
grep -Eq 'ControllerRootView\(viewModel: controllerViewModel\)' TermiRustMobile/App/TermiRustMobileApp.swift || {
  printf 'Unified navigation does not expose paired Devices.\n' >&2
  exit 1
}
grep -Eq 'TabView\(selection: \$destination\)' TermiRustMobile/App/TermiRustMobileApp.swift || {
  printf 'Unified navigation is not bound to the canonical root destination.\n' >&2
  exit 1
}

xcodegen generate --spec project.yml >/dev/null
project_file=TermiRustMobile.xcodeproj/project.pbxproj
for marker in MobileSSHSession TmuxBootstrap HostListViewModel ControllerRootView TermiRustMobileCrypto TermiRustControllerSecurity NIOSSH; do
  grep -q "$marker" "$project_file" || {
    printf 'Generated unified target is missing %s.\n' "$marker" >&2
    exit 1
  }
done

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CRYPTO_HEADERS="Frameworks/TermiRustMobileCrypto.xcframework/ios-arm64/Headers"
SECURITY_HEADERS="Frameworks/TermiRustControllerSecurity.xcframework/ios-arm64/Headers"
PLATFORM="/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer"
TEMP_MODULE="$(mktemp -d "${TMPDIR:-/tmp}/termirust-ios-unified.XXXXXX")"
trap 'find "$TEMP_MODULE" -depth -delete 2>/dev/null || true' EXIT

cat >"$TEMP_MODULE/DirectSSHCompileStub.swift" <<'SWIFT'
import Foundation

enum TerminalConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

protocol MobileSSHConnecting: Sendable {
    func connect(
        host: MobileHost,
        knownHost: MobileKnownHost?,
        onOutput: @escaping @Sendable (Data) -> Void
    ) async throws
    func send(_ bytes: Data) async throws
    func resize(columns: Int, rows: Int) async throws
    func disconnect() async
}

final class DirectSSHSessionClient: MobileSSHConnecting, @unchecked Sendable {
    init(secretStore: SecretStoring? = nil) {}
    func connect(
        host: MobileHost,
        knownHost: MobileKnownHost?,
        onOutput: @escaping @Sendable (Data) -> Void
    ) async throws {}
    func send(_ bytes: Data) async throws {}
    func resize(columns: Int, rows: Int) async throws {}
    func disconnect() async {}
}
SWIFT

UNIFIED_SOURCES=(
  TermiRustMobile/App/TermiRustMobileApp.swift
  TermiRustMobile/Generated/TermiRustControllerSecurity.swift
  TermiRustMobile/Models/ControllerModels.swift
  TermiRustMobile/Models/ControllerRemoteRoute.swift
  TermiRustMobile/Models/ControllerRemoteRouteConfiguration.swift
  TermiRustMobile/Models/MobileRouteContract.swift
  TermiRustMobile/Models/MobileCrossRouteAcceptance.swift
  TermiRustMobile/Models/MobileVaultModels.swift
  TermiRustMobile/Security/ControllerKeychainBlobStore.swift
  TermiRustMobile/Security/ControllerRouteCredentialStore.swift
  TermiRustMobile/Security/KeychainSecretStore.swift
  TermiRustMobile/Security/MobileDeviceIdentityStore.swift
  TermiRustMobile/SSH/TmuxBootstrap.swift
  TermiRustMobile/Terminal/BoundedTerminalBuffer.swift
  TermiRustMobile/Terminal/GeneratedTerminalCellWidth.swift
  TermiRustMobile/Terminal/TerminalInteraction.swift
  TermiRustMobile/Terminal/TerminalAcceptance.swift
  TermiRustMobile/Terminal/TerminalBuffer.swift
  TermiRustMobile/Terminal/TerminalGrid.swift
  TermiRustMobile/Terminal/TerminalInputEncoding.swift
  TermiRustMobile/ViewModels/ControllerTerminalViewModel.swift
  TermiRustMobile/ViewModels/ControllerViewModel.swift
  TermiRustMobile/ViewModels/HostListViewModel.swift
  TermiRustMobile/Vault/EncryptedVaultStore.swift
  TermiRustMobile/Vault/MobileVaultImporter.swift
  TermiRustMobile/Vault/NativeMobileVaultDecryptor.swift
  TermiRustMobile/Controller/ControllerFleetCache.swift
  TermiRustMobile/Controller/AppleControllerRouteCoordinator.swift
  TermiRustMobile/Controller/PairedHostStore.swift
  TermiRustMobile/Controller/ControllerRetryPolicy.swift
  TermiRustMobile/Controller/ControllerReadOnlyAttach.swift
  TermiRustMobile/Controller/ControllerWriterControl.swift
  TermiRustMobile/Controller/ControllerConnectionActor.swift
  TermiRustMobile/Views/ContentView.swift
  TermiRustMobile/Views/ControllerPresentation.swift
  TermiRustMobile/Views/ControllerQRCodeScanner.swift
  TermiRustMobile/Views/ControllerReadOnlyTerminalView.swift
  TermiRustMobile/Views/ControllerRootView.swift
  TermiRustMobile/Views/ControllerTerminalInputView.swift
  TermiRustMobile/Views/HostListView.swift
  TermiRustMobile/Views/TerminalSessionView.swift
  "$TEMP_MODULE/DirectSSHCompileStub.swift"
)

xcrun xcstringstool compile \
  TermiRustMobile/Localizable.xcstrings \
  --output-directory "$TEMP_MODULE/localization" \
  --dry-run >/dev/null
xcrun swiftc \
  -emit-module \
  -parse-as-library \
  -enable-testing \
  -module-name TermiRustMobile \
  -swift-version 6 \
  -strict-concurrency=complete \
  -target arm64-apple-ios17.0 \
  -sdk "$SDK" \
  -I "$CRYPTO_HEADERS" \
  -I "$SECURITY_HEADERS" \
  -emit-module-path "$TEMP_MODULE/TermiRustMobile.swiftmodule" \
  "${UNIFIED_SOURCES[@]}"

xcrun swiftc \
  -typecheck \
  -swift-version 6 \
  -strict-concurrency=complete \
  -target arm64-apple-ios17.0 \
  -sdk "$SDK" \
  -F "$PLATFORM/Library/Frameworks" \
  -I "$PLATFORM/usr/lib" \
  -I "$TEMP_MODULE" \
  -I "$CRYPTO_HEADERS" \
  -I "$SECURITY_HEADERS" \
  TermiRustMobileTests/UnifiedRouteLifecycleTests.swift

xcrun swiftc \
  -typecheck \
  -swift-version 6 \
  -strict-concurrency=complete \
  -target arm64-apple-ios17.0 \
  -sdk "$SDK" \
  -F "$PLATFORM/Library/Frameworks" \
  -I "$PLATFORM/usr/lib" \
  -I "$TEMP_MODULE" \
  -I "$CRYPTO_HEADERS" \
  -I "$SECURITY_HEADERS" \
  TermiRustMobileTests/AppleControllerRouteTests.swift

xcrun swiftc -frontend -parse $(find TermiRustMobile TermiRustMobileTests -name '*.swift' -print)

BUILD_LOG="$TEMP_MODULE/xcodebuild.log"
set +e
xcodebuild build \
  -project TermiRustMobile.xcodeproj \
  -scheme TermiRustMobile \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO >"$BUILD_LOG" 2>&1
BUILD_STATUS=$?
set -e
if [[ "$BUILD_STATUS" == "0" ]]; then
  printf 'Unified iOS device build passed.\n'
elif grep -Eq 'Unable to find a destination|Found no destinations' "$BUILD_LOG" \
  && [[ "$REQUIRE_RUNTIME" != "1" ]]; then
  printf 'Unified source and lifecycle tests type-checked; this Xcode has no eligible iOS destination.\n'
elif grep -Eq 'Unable to find a destination|Found no destinations' "$BUILD_LOG"; then
  printf 'No eligible iOS destination is installed; runtime verification is required.\n' >&2
  exit 1
else
  cat "$BUILD_LOG" >&2
  exit "$BUILD_STATUS"
fi

git diff --check
printf 'Unified iOS target includes direct SSH Connections and paired Device Sessions.\n'
