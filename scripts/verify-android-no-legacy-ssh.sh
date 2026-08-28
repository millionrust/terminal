#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VARIANT=${2:-controllerDebug}

case "${1:-}" in
  --variant) ;;
  "") ;;
  *) echo "usage: $0 [--variant controllerDebug]" >&2; exit 2 ;;
esac

case "$VARIANT" in
  controllerDebug|controllerRelease) ;;
  *) echo "verification is restricted to a Controller variant" >&2; exit 2 ;;
esac

if find "$ROOT/app/src/main" "$ROOT/app/src/controller" -type f \
  \( -name '*.kt' -o -name '*.java' -o -name '*.xml' \) -print0 |
  xargs -0 grep -En 'DirectSshSessionClient|TmuxBootstrap|net\.schmizz|com\.hierynomus' >/dev/null 2>&1; then
  echo "legacy SSH reference found in Controller sources" >&2
  exit 1
fi

if find "$ROOT/app/src/main" "$ROOT/app/src/controller" -type f \
  -name 'libtermirust_mobile_ffi.so' -print -quit | grep -q .; then
  echo "legacy direct-SSH JNI library found in Controller sources" >&2
  exit 1
fi

CONFIG="${VARIANT}RuntimeClasspath"
REPORT=$(mktemp)
trap 'rm -f "$REPORT"' EXIT HUP INT TERM
(
  cd "$ROOT"
  ANDROID_HOME=${ANDROID_HOME:-"$HOME/Library/Android/sdk"} ./gradlew \
    ":app:dependencies" --configuration "$CONFIG" --console=plain >"$REPORT"
)
if grep -Eiq 'sshj|bcpkix|eddsa' "$REPORT"; then
  echo "legacy SSH dependency found in $CONFIG" >&2
  exit 1
fi

echo "$VARIANT contains no legacy direct-SSH source or dependency"
