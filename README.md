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

## Troubleshooting

### Claude Code text is highlighted, but Control + F cannot translate it

If SelectTranslate opens but displays `Select text before pressing Control + F. Some apps do not expose selected text through Accessibility.`, check whether the terminal can actually copy the selection. In Apple Terminal, open Edit > Copy: if Copy is disabled despite a visible highlight, the highlight may belong to Claude Code's fullscreen UI rather than Terminal's native text selection.

Claude Code's fullscreen mode can capture mouse selection, preventing SelectTranslate from reading or copying that highlight. This is a source-selection issue, not necessarily a SelectTranslate Accessibility permission issue. See the related [Claude Code issue](https://github.com/anthropics/claude-code/issues/76902).

To use ordinary drag selection without a modifier key:

1. Open `~/.claude/settings.json`.
2. Change the top-level `"tui": "fullscreen"` setting to `"tui": "default"`. If the key is absent, add it. Preserve the other settings; the following is only the relevant entry, not a replacement for the entire file:

   ```json
   "tui": "default"
   ```

3. Restart Claude Code. This switches away from its fullscreen UI.
4. Drag to select text normally, then press `Control + F`.

If you want to keep fullscreen mode, use the terminal's native selection instead: hold Fn (Globe) while dragging in Apple Terminal, or Shift while dragging in cmux. Release the modifier before pressing `Control + F`. In Apple Terminal, Edit > Copy should be enabled for the native selection.

During investigation, translation worked in Apple Terminal with Fn-drag even after all experimental SelectTranslate capture changes were reverted. Changing Claude Code to `"tui": "default"` also restored translation with ordinary drag selection. No Terminal-specific SelectTranslate workaround was needed for this case. Other terminal applications or CLI tools may behave differently.

### cmux requires Shift-drag to select text

When a terminal CLI captures mouse input, ordinary dragging may not create a native terminal selection. Shift-drag is the temporary workaround in cmux. To allow ordinary drag selection even when a CLI requests mouse input, disable mouse reporting:

1. Open or create `~/.config/ghostty/config`, which cmux reads for terminal settings (not `~/.config/cmux/cmux.json`). Preserve other settings and add or update this line:

   ```ini
   mouse-reporting = false
   ```

2. Reload cmux configuration with `Command + Shift + ,`. If existing terminals do not pick up the change, restart cmux after saving your work.
3. Drag to select text without Shift, then press `Control + F`.

This prevents mouse events from reaching terminal CLI applications. Mouse-driven clicks and scrolling inside TUIs such as editors or Claude Code may no longer work as before; terminal-native selection and scrolling remain separate. The shared Ghostty config can also affect Ghostty itself. To restore mouse reporting, set `mouse-reporting = true` and reload, then use Shift-drag when native selection is needed.

See [cmux configuration](https://cmux.com/docs/configuration) for config locations and reloading, and [Ghostty's mouse-reporting reference](https://ghostty.org/docs/config/reference#mouse-reporting) for the option's behavior. This is a cmux/Ghostty setting, not an Apple Terminal setting.

### Codex stops scrolling after disabling mouse reporting in cmux

With `mouse-reporting = false`, Codex's alternate-screen UI may stop responding to mouse-wheel or trackpad scrolling because mouse events no longer reach the CLI. Switching mouse reporting back to `true` restored scrolling during investigation, but required Shift-drag for native text selection again.

To keep both scrolling and ordinary drag selection, use Codex's inline terminal mode together with disabled mouse reporting:

1. Keep `mouse-reporting = false` in `~/.config/ghostty/config` and reload cmux with `Command + Shift + ,`.
2. Open `~/.codex/config.toml` and add or update this entry under `[tui]`:

   ```toml
   [tui]
   alternate_screen = "never"
   ```

   Preserve the other settings. If `[tui]` already exists, add the entry to that section rather than creating a duplicate table.

3. Exit Codex and restart it. To return to the latest conversation, run `codex resume --last`. Reloading cmux alone does not apply this Codex startup setting to an already-running session.
4. Verify that mouse-wheel or trackpad scrolling works, then drag to select text without Shift and press `Control + F`.

This combination was confirmed to allow both scrolling and translation without Shift in cmux. Codex uses the terminal's normal scrollback instead of the alternate screen; other TUIs can still lose mouse-driven features while mouse reporting is disabled. Claude Code is configured separately: use `"tui": "default"` as described above.

See [OpenAI's advanced configuration documentation](https://learn.chatgpt.com/docs/config-file/config-advanced) for `tui.alternate_screen`. To restore Codex's default display behavior, remove the entry or set it to `"auto"`, then restart Codex. If you also restore `mouse-reporting = true`, use Shift-drag for native selection when a CLI captures mouse input.

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
