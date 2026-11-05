#!/bin/sh
# Prepares the PLaMo environment and downloads one PLaMo 3 Translate size.
# Usage: ./scripts/install-plamo-deps.sh [0.8b|2b|8b|31b]   (default: 2b)
set -eu

SIZE="${1:-2b}"
case "$SIZE" in
  0.8b|2b|8b|31b) ;;
  *)
    echo "Unknown size: $SIZE (choose 0.8b, 2b, 8b or 31b)" >&2
    exit 1
    ;;
esac

APP_SUPPORT="$HOME/Library/Application Support/SelectTranslate"
VENV="$APP_SUPPORT/PLaMoEnvironment"
HF_HOME="$APP_SUPPORT/HuggingFace"
REPO="pfnet/plamo-3-translate-$SIZE-MLX-4bit"

mkdir -p "$APP_SUPPORT" "$HF_HOME" "$APP_SUPPORT/PLaMo3Models"

if [ ! -x "$VENV/bin/python3" ]; then
  python3 -m venv "$VENV"
fi

"$VENV/bin/python3" -m pip install -U mlx-lm mlx transformers numba
printf 'ready\n' > "$APP_SUPPORT/PLaMo3EnvironmentReady"

HF_HOME="$HF_HOME" "$VENV/bin/python3" -c \
  'import sys; from huggingface_hub import snapshot_download; print(snapshot_download(sys.argv[1]))' \
  "$REPO"

printf '%s\n' "$REPO" > "$APP_SUPPORT/PLaMo3Models/$SIZE.ready"
