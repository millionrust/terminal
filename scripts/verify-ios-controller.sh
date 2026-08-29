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
      printf 'Usage: %s --stage pairing-fleet|readonly-terminal|writer-controls|terminal-conformance|terminal-interaction|universal-session [--require-runtime]\n' "$0" >&2
      exit 2
      ;;
  esac
done

[[ "$STAGE" == "pairing-fleet" || "$STAGE" == "readonly-terminal" || "$STAGE" == "writer-controls" || "$STAGE" == "terminal-conformance" || "$STAGE" == "terminal-interaction" || "$STAGE" == "universal-session" ]] || {
  printf 'Stage must be pairing-fleet, readonly-terminal, writer-controls, terminal-conformance, terminal-interaction, or universal-session.\n' >&2
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
[[ -f TermiRustMobile/Localizable.xcstrings ]] || {
  printf 'Controller string catalog is missing.\n' >&2
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
xcrun xcstringstool compile \
  TermiRustMobile/Localizable.xcstrings \
  --output-directory "$TEMP_MODULE/localization" \
  --dry-run >/dev/null

CONTROLLER_SOURCES=(
  TermiRustMobile/App/TermiRustMobileApp.swift
  TermiRustMobile/Generated/TermiRustControllerSecurity.swift
  TermiRustMobile/Models/ControllerModels.swift
  TermiRustMobile/Controller/ControllerFleetCache.swift
  TermiRustMobile/Controller/PairedHostStore.swift
  TermiRustMobile/Security/ControllerKeychainBlobStore.swift
  TermiRustMobile/Controller/ControllerRetryPolicy.swift
  TermiRustMobile/Controller/ControllerReadOnlyAttach.swift
  TermiRustMobile/Controller/ControllerWriterControl.swift
  TermiRustMobile/Terminal/BoundedTerminalBuffer.swift
  TermiRustMobile/Terminal/GeneratedTerminalCellWidth.swift
  TermiRustMobile/Terminal/TerminalInteraction.swift
  TermiRustMobile/Controller/ControllerConnectionActor.swift
  TermiRustMobile/ViewModels/ControllerViewModel.swift
  TermiRustMobile/ViewModels/ControllerTerminalViewModel.swift
  TermiRustMobile/Views/ControllerPresentation.swift
  TermiRustMobile/Views/ControllerRootView.swift
  TermiRustMobile/Views/ControllerReadOnlyTerminalView.swift
  TermiRustMobile/Views/ControllerTerminalInputView.swift
  TermiRustMobile/Views/ControllerQRCodeScanner.swift
)
TEST_SOURCES=(
  TermiRustMobileTests/ControllerFleetCacheTests.swift
  TermiRustMobileTests/ControllerPairingFleetTests.swift
)
RUNTIME_TESTS=(
  -only-testing:TermiRustMobileTests/ControllerPairingFleetTests
  -only-testing:TermiRustMobileTests/ControllerFleetCacheTests
)
if [[ "$STAGE" == "readonly-terminal" || "$STAGE" == "writer-controls" || "$STAGE" == "terminal-conformance" || "$STAGE" == "terminal-interaction" || "$STAGE" == "universal-session" ]]; then
  TEST_SOURCES+=(TermiRustMobileTests/ControllerReadOnlyTerminalTests.swift)
  TEST_SOURCES+=(TermiRustMobileTests/BoundedTerminalBufferTests.swift)
  TEST_SOURCES+=(TermiRustMobileTests/ControllerTerminalViewModelTests.swift)
  RUNTIME_TESTS+=(-only-testing:TermiRustMobileTests/ControllerReadOnlyTerminalTests)
  RUNTIME_TESTS+=(-only-testing:TermiRustMobileTests/BoundedTerminalBufferTests)
  RUNTIME_TESTS+=(-only-testing:TermiRustMobileTests/ControllerTerminalViewModelTests)
fi
if [[ "$STAGE" == "terminal-conformance" || "$STAGE" == "terminal-interaction" ]]; then
  TEST_SOURCES+=(TermiRustMobileTests/TerminalConformanceV1Tests.swift)
  TEST_SOURCES+=(TermiRustMobileTests/TerminalConformanceV2Tests.swift)
  RUNTIME_TESTS+=(-only-testing:TermiRustMobileTests/TerminalConformanceV1Tests)
  RUNTIME_TESTS+=(-only-testing:TermiRustMobileTests/TerminalConformanceV2Tests)
fi

if [[ "$STAGE" == "terminal-interaction" ]]; then
  xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    TermiRustMobile/Controller/ControllerReadOnlyAttach.swift \
    TermiRustMobile/Terminal/GeneratedTerminalCellWidth.swift \
    TermiRustMobile/Terminal/BoundedTerminalBuffer.swift \
    TermiRustMobile/Terminal/TerminalInteraction.swift \
    scripts/terminal-interaction.swift \
    -o "$TEMP_MODULE/terminal-interaction"
  "$TEMP_MODULE/terminal-interaction" \
    TermiRustMobileTests/Fixtures/terminal-interaction-v1.json
fi
if [[ "$STAGE" == "terminal-interaction" ]]; then
  TEST_SOURCES+=(TermiRustMobileTests/TerminalInteractionTests.swift)
  RUNTIME_TESTS+=(-only-testing:TermiRustMobileTests/TerminalInteractionTests)
fi
if [[ "$STAGE" == "writer-controls" || "$STAGE" == "terminal-interaction" || "$STAGE" == "universal-session" ]]; then
  TEST_SOURCES+=(TermiRustMobileTests/ControllerWriterTests.swift)
  RUNTIME_TESTS+=(-only-testing:TermiRustMobileTests/ControllerWriterTests)
fi
if [[ "$STAGE" == "universal-session" ]]; then
  TEST_SOURCES+=(TermiRustMobileTests/UniversalSessionGoldenPathTests.swift)
  RUNTIME_TESTS+=(-only-testing:TermiRustMobileTests/UniversalSessionGoldenPathTests)
fi

xcrun swiftc \
  -emit-module \
  -parse-as-library \
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
  "${TEST_SOURCES[@]}"

xcrun swiftc -frontend -parse $(find TermiRustMobile TermiRustMobileTests -name '*.swift' -print)
git diff --check

if [[ "$STAGE" == "terminal-conformance" || "$STAGE" == "terminal-interaction" ]]; then
  xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    TermiRustMobile/Controller/ControllerReadOnlyAttach.swift \
    TermiRustMobile/Terminal/GeneratedTerminalCellWidth.swift \
    TermiRustMobile/Terminal/BoundedTerminalBuffer.swift \
    scripts/terminal-conformance-v1.swift \
    -o "$TEMP_MODULE/terminal-conformance-v1"
  "$TEMP_MODULE/terminal-conformance-v1" \
    TermiRustMobileTests/Fixtures/terminal-conformance-v1.json

  xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    TermiRustMobile/Controller/ControllerReadOnlyAttach.swift \
    TermiRustMobile/Terminal/GeneratedTerminalCellWidth.swift \
    TermiRustMobile/Terminal/BoundedTerminalBuffer.swift \
    scripts/terminal-conformance-v2.swift \
    -o "$TEMP_MODULE/terminal-conformance-v2"
  "$TEMP_MODULE/terminal-conformance-v2" \
    TermiRustMobileTests/Fixtures/terminal-conformance-v2.json
fi

SIMULATOR_NAME="$(
  xcrun simctl list devices available 2>/dev/null \
    | awk -F '[()]' '/iPhone/ { name=$1; sub(/^[[:space:]]+/, "", name); sub(/[[:space:]]+$/, "", name); print name; exit }'
)"
if [[ -n "$SIMULATOR_NAME" ]]; then
  xcodebuild test \
    -project TermiRustMobile.xcodeproj \
    -scheme TermiRustMobile \
    -destination "platform=iOS Simulator,name=$SIMULATOR_NAME,OS=latest" \
    "${RUNTIME_TESTS[@]}" \
    CODE_SIGNING_ALLOWED=NO
  printf 'Controller iOS runtime tests passed on %s.\n' "$SIMULATOR_NAME"
elif [[ "$REQUIRE_RUNTIME" == "1" ]]; then
  printf 'No available iPhone simulator runtime. Runtime verification is required.\n' >&2
  exit 1
else
  printf 'Controller source and test type-checks passed; no iPhone simulator runtime is installed.\n'
fi
