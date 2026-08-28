#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE=""
REQUIRE_RUNTIME="${REQUIRE_IOS_RUNTIME:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage)
      [[ $# -ge 2 ]] || { printf 'Missing value for --stage.\n' >&2; exit 2; }
      STAGE="$2"
      shift 2
      ;;
    --require-runtime)
      REQUIRE_RUNTIME=1
      shift
      ;;
    *)
      printf 'Usage: %s --stage pairing-fleet [--require-runtime]\n' "$0" >&2
      exit 2
      ;;
  esac
done

[[ "$STAGE" == "pairing-fleet" ]] || {
  printf 'Only --stage pairing-fleet is supported.\n' >&2
  exit 2
}

cd "$ROOT_DIR"
[[ -d Frameworks/TermiRustControllerSecurity.xcframework ]] || {
  printf 'Controller security XCFramework is missing.\n' >&2
  exit 1
}
[[ -f TermiRustMobile/Generated/TermiRustControllerSecurity.swift ]] || {
  printf 'Generated Controller Swift binding is missing.\n' >&2
  exit 1
}
command -v xcodegen >/dev/null || {
  printf 'xcodegen is required.\n' >&2
  exit 1
}

xcodegen generate --spec project.yml >/dev/null

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
HEADERS="Frameworks/TermiRustControllerSecurity.xcframework/ios-arm64/Headers"
PLATFORM="/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer"
TEMP_MODULE="$(mktemp -d "${TMPDIR:-/tmp}/termirust-ios-controller.XXXXXX")"
trap 'find "$TEMP_MODULE" -depth -delete 2>/dev/null || true' EXIT

CONTROLLER_SOURCES=(
  TermiRustMobile/Generated/TermiRustControllerSecurity.swift
  TermiRustMobile/Models/ControllerModels.swift
  TermiRustMobile/Controller/ControllerFleetCache.swift
  TermiRustMobile/Controller/PairedHostStore.swift
  TermiRustMobile/Security/ControllerKeychainBlobStore.swift
  TermiRustMobile/Controller/ControllerRetryPolicy.swift
  TermiRustMobile/Controller/ControllerConnectionActor.swift
  TermiRustMobile/ViewModels/ControllerViewModel.swift
  TermiRustMobile/Views/ControllerRootView.swift
  TermiRustMobile/Views/ControllerQRCodeScanner.swift
)

xcrun swiftc \
  -emit-module \
  -enable-testing \
  -module-name TermiRustMobile \
  -swift-version 6 \
  -strict-concurrency=complete \
  -target arm64-apple-ios17.0 \
  -sdk "$SDK" \
  -I "$HEADERS" \
  -emit-module-path "$TEMP_MODULE/TermiRustMobile.swiftmodule" \
  "${CONTROLLER_SOURCES[@]}"

xcrun swiftc \
  -typecheck \
  -swift-version 6 \
  -strict-concurrency=complete \
  -target arm64-apple-ios17.0 \
  -sdk "$SDK" \
  -F "$PLATFORM/Library/Frameworks" \
  -I "$PLATFORM/usr/lib" \
  -I "$TEMP_MODULE" \
  -I "$HEADERS" \
  TermiRustMobileTests/ControllerFleetCacheTests.swift \
  TermiRustMobileTests/ControllerPairingFleetTests.swift

xcrun swiftc -frontend -parse $(find TermiRustMobile TermiRustMobileTests -name '*.swift' -print)
git diff --check

SIMULATOR_NAME="$(
  xcrun simctl list devices available 2>/dev/null \
    | awk -F '[()]' '/iPhone/ { name=$1; sub(/^[[:space:]]+/, "", name); sub(/[[:space:]]+$/, "", name); print name; exit }'
)"
if [[ -n "$SIMULATOR_NAME" ]]; then
  xcodebuild test \
    -project TermiRustMobile.xcodeproj \
    -scheme TermiRustMobile \
    -destination "platform=iOS Simulator,name=$SIMULATOR_NAME,OS=latest" \
    -only-testing:TermiRustMobileTests/ControllerPairingFleetTests \
    -only-testing:TermiRustMobileTests/ControllerFleetCacheTests \
    CODE_SIGNING_ALLOWED=NO
  printf 'Controller iOS runtime tests passed on %s.\n' "$SIMULATOR_NAME"
elif [[ "$REQUIRE_RUNTIME" == "1" ]]; then
  printf 'No available iPhone simulator runtime. Runtime verification is required.\n' >&2
  exit 1
else
  printf 'Controller source and test type-checks passed; no iPhone simulator runtime is installed.\n'
fi
