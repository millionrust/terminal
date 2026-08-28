#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="Debug"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      [[ $# -ge 2 ]] || { printf 'Missing configuration value.\n' >&2; exit 2; }
      CONFIGURATION="$2"
      shift 2
      ;;
    *)
      printf 'Usage: %s [--configuration Debug|Release]\n' "$0" >&2
      exit 2
      ;;
  esac
done

[[ "$CONFIGURATION" == "Debug" || "$CONFIGURATION" == "Release" ]] || {
  printf 'Configuration must be Debug or Release.\n' >&2
  exit 2
}

cd "$ROOT_DIR"
command -v xcodegen >/dev/null || { printf 'xcodegen is required.\n' >&2; exit 1; }

legacy_files=(
  TermiRustMobile/SSH/MobileSSHSession.swift
  TermiRustMobile/SSH/TmuxBootstrap.swift
  TermiRustMobile/ViewModels/HostListViewModel.swift
  TermiRustMobile/Views/ContentView.swift
  TermiRustMobile/Views/TerminalSessionView.swift
)
for path in "${legacy_files[@]}"; do
  [[ -f "$path" ]] || { printf 'Preserved legacy source is missing: %s\n' "$path" >&2; exit 1; }
done

grep -Eq '^[[:space:]]+LEGACY_DIRECT_SSH:[[:space:]]+0$' project.yml || {
  printf 'Standard build must set LEGACY_DIRECT_SSH=0.\n' >&2
  exit 1
}

if grep -Eq 'MobileSSHSession|TmuxBootstrap|DirectSSHSessionClient|HostListViewModel|ContentView' \
  TermiRustMobile/App/TermiRustMobileApp.swift \
  TermiRustMobile/Views/ControllerRootView.swift; then
  printf 'Standard Controller navigation references legacy direct SSH.\n' >&2
  exit 1
fi

xcodegen generate --spec project.yml >/dev/null
project_file=TermiRustMobile.xcodeproj/project.pbxproj
if grep -Eq 'MobileSSHSession|TmuxBootstrap|HostListViewModel|TerminalSessionView|TermiRustMobileCrypto|swift-nio-ssh' "$project_file"; then
  printf 'Generated standard target compiles or links legacy direct SSH.\n' >&2
  exit 1
fi

printf 'Standard %s Controller build excludes legacy direct SSH while preserving its source.\n' "$CONFIGURATION"
