# CodexTranslator

macOS utility app that translates selected text with `codex exec` and shows the source and translated text in a floating panel.

## Requirements

- macOS 13 or later
- Xcode command line tools or Xcode
- Codex CLI installed and logged in

## Build and Launch as a Mac App

```sh
./scripts/build-app.sh
open build/CodexTranslator.app
```

This launches CodexTranslator as a regular macOS app with a Dock icon and normal application menu.

## Local run

```sh
swift run CodexTranslator
```

`swift run` is useful during development, but it runs the executable directly from Terminal. Use the `.app` flow above for normal app behavior.

The translation window is resizable.

## Usage

1. Select text in any app.
2. Press `Control + F`.
3. The app reads the selection through macOS Accessibility, translates with `codex exec`, then shows the original and translated text in a floating panel.

Japanese text is translated to English. Text without Japanese characters is translated to Japanese.

The app does not use `Command + C` or the clipboard to read selected text. Some apps do not expose selected text through Accessibility; in those apps CodexTranslator will show a no-selection error.

Use the `Effort` segmented control in the panel to choose the Codex reasoning effort. When a translation is already displayed, changing the effort reruns that same source text. The app saves the selected value.

Use the retranslation button in the `Translation` header to translate the current translation back to the original language. The back translation appears at the bottom of the `Translation` area.

Use `Codex` > `Settings...` to edit the prompt template. The template supports `{{instruction}}` for the current translation direction and `{{text}}` for the selected text.

## Permissions

macOS Accessibility permission is required so the app can read selected text from the frontmost app.

If the shortcut shows a permission error:

1. Open `CodexTranslator` > `Actions` > `Open Accessibility Settings`.
2. Approve the macOS prompt, or enable `CodexTranslator` in the Accessibility list.
3. Quit and reopen CodexTranslator.
4. Press `Control + F` again.

`swift run CodexTranslator` and `open build/CodexTranslator.app` are treated as different apps by macOS privacy permissions. Grant permission to the `.app` version when using the normal launch flow.

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

The saved prompt template is rendered and sent to `codex exec` over stdin.
