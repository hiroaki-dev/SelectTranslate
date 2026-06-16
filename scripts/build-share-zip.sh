#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_NAME="SelectTranslate"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
ZIP_PATH="$ROOT_DIR/$APP_NAME.zip"

"$ROOT_DIR/scripts/build-app.sh"

xattr -cr "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$ZIP_PATH"
(
  cd "$ROOT_DIR/build"
  /usr/bin/zip -r -X "$ZIP_PATH" "$APP_NAME.app" >/dev/null
)

TMP_DIR="$(mktemp -d /tmp/selecttranslate-share.XXXXXX)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

/usr/bin/unzip -q "$ZIP_PATH" -d "$TMP_DIR"
codesign --verify --deep --strict --verbose=2 "$TMP_DIR/$APP_NAME.app"

printf 'Built %s\n' "$ZIP_PATH"
printf 'SHA-256: '
shasum -a 256 "$ZIP_PATH" | awk '{print $1}'
