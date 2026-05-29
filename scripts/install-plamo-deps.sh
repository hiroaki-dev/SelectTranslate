#!/bin/sh
set -eu

APP_SUPPORT="$HOME/Library/Application Support/CodexTranslator"
VENV="$APP_SUPPORT/PLaMoEnvironment"
HF_HOME="$APP_SUPPORT/HuggingFace"

mkdir -p "$APP_SUPPORT" "$HF_HOME"

if [ ! -x "$VENV/bin/python3" ]; then
  python3 -m venv "$VENV"
fi

"$VENV/bin/python3" -m pip install -U mlx-lm numba
HF_HOME="$HF_HOME" "$VENV/bin/python3" -m mlx_lm generate \
  --model mlx-community/plamo-2-translate \
  --trust-remote-code \
  --extra-eos-token '<|plamo:op|>' \
  --prompt 'こんにちは'

printf 'ready\n' > "$APP_SUPPORT/PLaMoSetupComplete"
