# SelectTranslate

macOS utility app that translates selected text with `codex exec`, `claude -p`, local PLaMo MLX, or an OpenAI-compatible chat completions API, and shows the source and translated text in a floating panel.

## Requirements

- macOS 13 or later
- Xcode command line tools or Xcode
- Codex CLI installed and logged in for the Codex engine
- Claude CLI installed and logged in for the Claude engine
- Optional for local PLaMo: Apple Silicon Mac and Python 3

## Build and Launch as a Mac App

```sh
./scripts/build-app.sh
open build/SelectTranslate.app
```

This launches SelectTranslate as a regular macOS app with a Dock icon and normal application menu.

## Build a Shareable Zip

```sh
./scripts/build-share-zip.sh
```

This creates `SelectTranslate.zip` at the repository root. The script builds the app, applies an ad-hoc signature, removes local extended attributes, zips the `.app`, extracts it to a temporary directory, verifies the signature again, and prints the SHA-256 digest.

The zip is not signed with an Apple Developer ID and is not notarized. macOS may require right-click > Open, or approval in System Settings > Privacy & Security, on first launch.

## Local run

```sh
swift run SelectTranslate
```

`swift run` is useful during development, but it runs the executable directly from Terminal. Use the `.app` flow above for normal app behavior.

The translation window is resizable.

## Usage

1. Select text in any app.
2. Press `Control + F`.
3. The app reads the selection through macOS Accessibility, translates with the selected engine, then shows the original and translated text in a floating panel.

Japanese text is translated to English. Text without Japanese characters is translated to Japanese.

The app first reads selected text through Accessibility without touching the clipboard. If an app does not expose selected text through Accessibility, SelectTranslate preserves the current clipboard, sends `Command + C`, captures the selected text, and restores the previous clipboard immediately before translation starts.

Use the `Engine` segmented control in the panel or `SelectTranslate` > `Settings...` to switch between `Codex`, `Claude`, `PLaMo`, and `API`. PLaMo cannot be selected until `Prepare PLaMo` has completed in Settings. When a translation is already displayed, changing the engine reruns that same source text. The app saves the selected value.

PLaMo and API translations stream partial output into the translation pane while generation is running. Codex and Claude translations are shown when the CLI returns its final message.

Use the `Effort` segmented control in the panel to choose the Codex or Claude reasoning effort. It is shown only for the Codex and Claude engines. When a CLI translation is already displayed, changing the effort reruns that same source text. The app saves the selected value.

Use the retranslation button in the `Translation` header to translate the current translation back to the original language. The back translation appears at the bottom of the `Translation` area.

Use `SelectTranslate` > `Settings...` to create multiple shortcut sets. Each set has a display name, global shortcut, and prompt template. The template supports `{{instruction}}` for the current translation direction and `{{text}}` for the selected text.

The default shortcut set preserves the existing `Control + F` behavior. Add another shortcut set when you want a different translation style, such as stricter technical terminology or a more natural rewrite.

## Permissions

macOS Accessibility permission is required so the app can read selected text from the current focused element or app.

On launch, SelectTranslate asks macOS to show the Accessibility prompt if the permission is missing.

If the shortcut shows a permission error:

1. Press `Control + F`; if permission is missing, SelectTranslate asks macOS to show the Accessibility prompt.
2. Approve the macOS prompt, or enable `SelectTranslate` in the Accessibility list.
3. SelectTranslate retries the pending translation automatically after permission is enabled.

SelectTranslate requests the permission prompt each time `Control + F` is pressed without Accessibility permission. Use `SelectTranslate` > `Actions` > `Open Accessibility Settings` to request it again or open the settings page manually.

`swift run SelectTranslate` and `open build/SelectTranslate.app` are treated as different apps by macOS privacy permissions. Grant permission to the `.app` version when using the normal launch flow.

## Codex command

The app runs Codex with:

```sh
codex exec --ignore-user-config --skip-git-repo-check --cd <application-support-workspace> --output-last-message <temp-file> -
```

`--ignore-user-config` prevents Codex from reading project entries in `~/.codex/config.toml`, including entries under protected folders such as Downloads. `--cd` is fixed to SelectTranslate's Application Support workspace so the app does not use the current Terminal or Finder directory. `--skip-git-repo-check` avoids the trusted-directory error in that translation-only workspace.

The selected panel effort is passed as:

```sh
-c 'model_reasoning_effort="<effort>"'
```

If a Codex model is configured in Settings, the app also passes:

```sh
--model <model>
```

The active shortcut set's prompt template is rendered and sent to `codex exec` over stdin.

## Claude command

The app runs Claude with:

```sh
claude -p --safe-mode --no-session-persistence --output-format text --effort <effort>
```

If a Claude model is configured in Settings, the app also passes:

```sh
--model <model>
```

The active shortcut set's prompt template is rendered and sent to `claude -p` over stdin.

## PLaMo command

The PLaMo engine uses [`mlx-community/plamo-2-translate`](https://huggingface.co/mlx-community/plamo-2-translate), a 4-bit quantized PLaMo Translation Model for MLX on Apple Silicon. Review the model card and PLaMo community license before use.

Built with PLaMo.

The PLaMo model is not bundled with this repository or the app bundle created by `./scripts/build-app.sh`. When you run `Prepare PLaMo`, the app downloads the model into your local Application Support directory. The PLaMo model is governed by the PLaMo community license, not by SelectTranslate's Apache License 2.0. Commercial use may require additional steps described by Preferred Networks.

Run `Prepare PLaMo` in Settings before selecting the PLaMo engine. SelectTranslate creates an app-local Python environment, installs `mlx-lm`, `numba`, and `torch`, and downloads the model. Settings shows the active setup step and live command output, including download progress reported by the underlying tools. The files are stored under:

```sh
~/Library/Application Support/SelectTranslate/
```

When upgrading from the old CodexTranslator name, the app moves the existing `~/Library/Application Support/CodexTranslator/` directory to `~/Library/Application Support/SelectTranslate/` if the new directory does not already exist.

For manual setup, you can run:

```sh
./scripts/install-plamo-deps.sh
```

After setup, the app runs:

```sh
~/Library/Application\ Support/SelectTranslate/PLaMoEnvironment/bin/python3 -m mlx_lm generate --model mlx-community/plamo-2-translate --trust-remote-code --extra-eos-token '<|plamo:op|>' --max-tokens <dynamic limit> --prompt '<selected text>'
```

SelectTranslate sets the PLaMo generation limit from the source text length, with a minimum of 1024 tokens and a maximum of 8192 tokens. This avoids the `mlx_lm generate` default limit, which is too small for longer translations.

PLaMo is a translation-specialized model and is not instruction-tuned for chat, so the app sends the selected text directly. Shortcut prompt templates are used by Codex and API, but ignored by PLaMo.

## OpenAI-compatible API

The `API` engine calls an OpenAI-compatible chat completions endpoint:

```sh
POST {base_url}/chat/completions
```

Configure these values in `SelectTranslate` > `Settings...`:

- `base_url`: include `/v1`, for example `http://localhost:1234/v1`
- `api_key`: optional; leave it blank for local servers that do not require authentication
- `model`: the model name served by the local API

The request uses a `system` message that asks for translation output only, and a `user` message rendered from the active shortcut set's prompt template. It uses `/chat/completions`, not `/completions`.

## License

SelectTranslate is released under the Apache License 2.0. See [LICENSE](LICENSE).

Third-party tools, Python packages, and models are governed by their own licenses and terms. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The source repository and the app bundle produced by `./scripts/build-app.sh` do not vendor the PLaMo model, Python environment, Python wheels, or Codex CLI. If you distribute a packaged app that bundles any of those components, include the corresponding license texts and notices for the bundled versions.
