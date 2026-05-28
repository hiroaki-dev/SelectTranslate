# CodexTranslator

macOS utility app that translates selected text with `codex exec` and shows the source and translated text in a floating panel.

## Requirements

- macOS 13 or later
- Xcode command line tools or Xcode
- Codex CLI installed and logged in

## Local run

```sh
swift run CodexTranslator
```

The app stays in the menu bar as `Codex` and shows a small ready panel on launch. Keep the terminal process running while you use the shortcut.

The translation window is resizable.

## Usage

1. Select text in any app.
2. Press `Control + F`.
3. The app copies the selection, restores your previous clipboard contents, translates with `codex exec`, then shows the original and translated text in a floating panel.

Japanese text is translated to English. Text without Japanese characters is translated to Japanese.

Use the `Effort` segmented control in the panel to choose the Codex reasoning effort. When a translation is already displayed, changing the effort reruns that same source text. The app saves the selected value.

Use the retranslation button in the `Translation` header to translate the current translation back to the original language. The back translation appears at the bottom of the `Translation` area.

## Permissions

macOS Accessibility permission is required so the app can send `Command + C` to the frontmost app.

If the shortcut shows a permission error:

1. Open the `Codex` menu bar item.
2. Choose `Open Accessibility Settings`.
3. Enable the running `CodexTranslator` executable.
4. Press `Control + F` again.

## Codex command

The app runs Codex with:

```sh
codex exec --skip-git-repo-check --cd <project-directory> --output-last-message <temp-file> -
```

`--skip-git-repo-check` avoids the trusted-directory error when translating outside a trusted Git repository.

The selected panel effort is passed as:

```sh
-c 'model_reasoning_effort="<effort>"'
```
