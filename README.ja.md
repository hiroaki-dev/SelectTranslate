# SelectTranslate

[English](README.md) | 日本語

選択したテキストを `codex exec`、`claude -p`、ローカルの PLaMo MLX、Apple Foundation Models、または OpenAI 互換の chat completions API で翻訳し、原文と訳文をフローティングパネルに表示する macOS ユーティリティアプリです。

## 動作環境

- macOS 13 以降
- Xcode Command Line Tools または Xcode
- Codex エンジンを使う場合: Codex CLI がインストール済みでログイン済みであること
- Claude エンジンを使う場合: Claude CLI がインストール済みでログイン済みであること
- ローカルの PLaMo を使う場合（任意）: Apple Silicon の Mac と Python 3
- Apple Foundation Models を使う場合（任意）: Apple Intelligence に対応した Mac の macOS 26 以降で、Apple Intelligence がオンになっていること

## Mac アプリとしてビルドして起動する

```sh
./scripts/build-app.sh
open build/SelectTranslate.app
```

SelectTranslate は Dock アイコンと通常のアプリケーションメニューを持つ、一般的な macOS アプリとして起動します。

## 配布用 zip を作る

```sh
./scripts/build-share-zip.sh
```

リポジトリのルートに `SelectTranslate.zip` が作られます。このスクリプトはアプリをビルドし、ad-hoc 署名を付け、ローカルの拡張属性を削除してから `.app` を zip にします。その後、一時ディレクトリに展開して署名を再検証し、SHA-256 ダイジェストを表示します。

この zip は Apple Developer ID で署名されておらず、公証（notarization）も受けていません。初回起動時に、右クリック > 開く、または システム設定 > プライバシーとセキュリティ での許可が必要になることがあります。

## ローカル実行

```sh
swift run SelectTranslate
```

`swift run` は開発中には便利ですが、実行ファイルをターミナルから直接起動します。通常のアプリとしての動作を確認するときは、上の `.app` の手順を使ってください。

翻訳ウィンドウはサイズを変更できます。

## 使い方

1. 任意のアプリでテキストを選択します。
2. `Control + F` を押します。
3. アプリが macOS のアクセシビリティ経由で選択範囲を読み取り、選択中のエンジンで翻訳して、原文と訳文をフローティングパネルに表示します。

日本語のテキストは英語に、日本語の文字を含まないテキストは日本語に翻訳されます。

アプリはまず、クリップボードに触れずにアクセシビリティ経由で選択テキストを読み取ります。アクセシビリティで選択テキストを公開していないアプリの場合は、現在のクリップボードを退避してから `Command + C` を送って選択テキストを取得し、翻訳を始める直前に元のクリップボードを復元します。

パネルの `Engine` セグメントコントロール、または `SelectTranslate` > `Settings...` で、`Codex`、`Claude`、`PLaMo`、`Apple`（Apple Foundation Models）、`API` を切り替えられます。PLaMo は、設定画面で `Prepare PLaMo` を完了するまで選択できません。`Apple` はオンデバイスのモデルが使えない間は選択できません。理由はボタンにカーソルを合わせるか、設定画面で確認できます。翻訳結果が表示されている状態でエンジンを変えると、同じ原文で翻訳し直します。選択した値は保存されます。

PLaMo、Apple Foundation Models、API の翻訳は、生成中の途中結果を翻訳欄に逐次表示します。Codex と Claude の翻訳は、CLI が最終メッセージを返した時点で表示されます。

パネルの `Effort` セグメントコントロールで、Codex または Claude の reasoning effort を選べます。これは Codex と Claude のエンジンでのみ表示されます。CLI での翻訳結果が表示されている状態で effort を変えると、同じ原文で翻訳し直します。選択した値は保存されます。

翻訳の実行中は、パネルのエンジン選択の横に停止ボタンが表示されます。クリックするか `Command + .` を押すと、裏で動いている CLI のプロセスや API リクエストも含めて翻訳を止められます。翻訳中に `Engine` や `Effort` を変えることもできます。その場合は実行中の翻訳を止めて、新しく選んだ設定で同じ原文を翻訳し直します。

`Translation` ヘッダーの再翻訳ボタンを使うと、現在の訳文を元の言語に翻訳し直します（逆翻訳）。逆翻訳の結果は `Translation` 欄の下部に表示されます。

`SelectTranslate` > `Settings...` では、ショートカットセットを複数作れます。各セットは表示名、グローバルショートカット、プロンプトテンプレートを持ちます。テンプレートでは、現在の翻訳方向を表す `{{instruction}}` と、選択テキストを表す `{{text}}` が使えます。

デフォルトのショートカットセットは、従来通りの `Control + F` の動作です。専門用語を厳密に扱う、より自然に書き直すなど、別の翻訳スタイルが欲しいときは、ショートカットセットを追加してください。

## 権限

アプリが現在フォーカスされている要素やアプリから選択テキストを読み取るために、macOS のアクセシビリティ権限が必要です。

起動時に権限がない場合、SelectTranslate は macOS にアクセシビリティの許可ダイアログを表示するよう要求します。

ショートカットで権限エラーが表示された場合:

1. `Control + F` を押します。権限がなければ、SelectTranslate が macOS にアクセシビリティの許可ダイアログを表示するよう要求します。
2. macOS のダイアログで許可するか、アクセシビリティの一覧で `SelectTranslate` を有効にします。
3. 権限が有効になると、SelectTranslate が保留中の翻訳を自動で再実行します。

アクセシビリティ権限がない状態で `Control + F` を押すたびに、SelectTranslate は許可ダイアログを要求します。もう一度要求したい場合や設定画面を手動で開きたい場合は、`SelectTranslate` > `Actions` > `Open Accessibility Settings` を使ってください。

macOS のプライバシー権限では、`swift run SelectTranslate` と `open build/SelectTranslate.app` は別のアプリとして扱われます。通常の起動手順を使う場合は、`.app` 版に権限を与えてください。

## トラブルシューティング

### Claude Code のテキストがハイライトされているのに、Control + F で翻訳できない

SelectTranslate が開いても `Select text before pressing Control + F. Some apps do not expose selected text through Accessibility.` と表示される場合は、ターミナルがその選択範囲を実際にコピーできるか確認してください。Apple のターミナルで 編集 > コピー を開き、ハイライトが見えているのにコピーが無効になっている場合、そのハイライトはターミナル本来のテキスト選択ではなく、Claude Code のフルスクリーン UI によるものかもしれません。

Claude Code のフルスクリーンモードはマウスによる選択を取り込むことがあり、その場合 SelectTranslate はハイライトを読み取ることもコピーすることもできません。これは選択元の問題で、SelectTranslate のアクセシビリティ権限の問題とは限りません。関連する [Claude Code の issue](https://github.com/anthropics/claude-code/issues/76902) も参照してください。

修飾キーなしの通常のドラッグで選択できるようにするには:

1. `~/.claude/settings.json` を開きます。
2. トップレベルの `"tui": "fullscreen"` を `"tui": "default"` に変更します。キーがなければ追加します。ほかの設定は残してください。以下は該当するエントリだけで、ファイル全体を置き換える内容ではありません:

   ```json
   "tui": "default"
   ```

3. Claude Code を再起動します。これでフルスクリーン UI ではなくなります。
4. 通常どおりドラッグしてテキストを選択し、`Control + F` を押します。

フルスクリーンモードのまま使いたい場合は、ターミナル本来の選択を使ってください。Apple のターミナルでは Fn（地球儀）キーを、cmux では Shift キーを押しながらドラッグします。`Control + F` を押す前に修飾キーを離してください。Apple のターミナルでは、本来の選択であれば 編集 > コピー が有効になっているはずです。

調査時には、SelectTranslate の実験的な取得方法の変更をすべて元に戻した状態でも、Apple のターミナルで Fn を押しながらのドラッグなら翻訳できました。Claude Code を `"tui": "default"` に変更した場合も、通常のドラッグ選択で翻訳できるようになりました。このケースでは、SelectTranslate 側にターミナル専用の回避策は必要ありませんでした。ほかのターミナルアプリや CLI ツールでは挙動が異なる場合があります。

### cmux でテキストを選択するのに Shift を押しながらドラッグする必要がある

ターミナル上の CLI がマウス入力を取り込んでいると、通常のドラッグではターミナル本来の選択にならないことがあります。cmux では、Shift を押しながらのドラッグが一時的な回避策です。CLI がマウス入力を要求していても通常のドラッグで選択できるようにするには、mouse reporting を無効にします:

1. cmux がターミナル設定を読む `~/.config/ghostty/config` を開くか作成します（`~/.config/cmux/cmux.json` ではありません）。ほかの設定は残したまま、次の行を追加または更新します:

   ```ini
   mouse-reporting = false
   ```

2. `Command + Shift + ,` で cmux の設定を再読み込みします。既存のターミナルに反映されない場合は、作業内容を保存してから cmux を再起動してください。
3. Shift を押さずにドラッグしてテキストを選択し、`Control + F` を押します。

この設定では、マウスイベントがターミナル上の CLI アプリに届かなくなります。エディタや Claude Code などの TUI 内でのマウスによるクリックやスクロールは、これまでどおりには動かなくなる場合があります。ターミナル本来の選択とスクロールは別に動作します。この Ghostty の設定ファイルは Ghostty 本体にも影響することがあります。mouse reporting を元に戻すには `mouse-reporting = true` にして再読み込みし、ターミナル本来の選択が必要なときは Shift を押しながらドラッグしてください。

設定ファイルの場所と再読み込みについては [cmux configuration](https://cmux.com/docs/configuration) を、このオプションの挙動については [Ghostty の mouse-reporting リファレンス](https://ghostty.org/docs/config/reference#mouse-reporting) を参照してください。これは cmux / Ghostty の設定で、Apple のターミナルの設定ではありません。

### cmux で mouse reporting を無効にしたら Codex でスクロールできなくなった

`mouse-reporting = false` にすると、マウスイベントが CLI に届かなくなるため、Codex の alternate screen UI がマウスホイールやトラックパッドのスクロールに反応しなくなることがあります。調査時には mouse reporting を `true` に戻すとスクロールできるようになりましたが、ターミナル本来の選択には再び Shift を押しながらのドラッグが必要になりました。

スクロールと通常のドラッグ選択を両立するには、mouse reporting を無効にしたまま、Codex のインラインのターミナルモードを使います:

1. `~/.config/ghostty/config` の `mouse-reporting = false` はそのままにし、`Command + Shift + ,` で cmux を再読み込みします。
2. `~/.codex/config.toml` を開き、`[tui]` に次のエントリを追加または更新します:

   ```toml
   [tui]
   alternate_screen = "never"
   ```

   ほかの設定は残してください。`[tui]` がすでにある場合は、テーブルを重複して作らず、既存のセクションにエントリを追加してください。

3. Codex を終了して再起動します。直前の会話に戻るには `codex resume --last` を実行します。cmux の再読み込みだけでは、起動済みのセッションにこの Codex の起動時設定は反映されません。
4. マウスホイールやトラックパッドでスクロールできることを確認してから、Shift を押さずにドラッグしてテキストを選択し、`Control + F` を押します。

この組み合わせで、cmux 上でスクロールと Shift なしの翻訳の両方ができることを確認しています。Codex は alternate screen ではなく、ターミナルの通常のスクロールバックを使うようになります。mouse reporting を無効にしている間、ほかの TUI ではマウスを使う機能が使えなくなることがあります。Claude Code は別に設定します。上で説明した `"tui": "default"` を使ってください。

`tui.alternate_screen` については [OpenAI の advanced configuration ドキュメント](https://learn.chatgpt.com/docs/config-file/config-advanced) を参照してください。Codex のデフォルトの表示に戻すには、このエントリを削除するか `"auto"` にして Codex を再起動します。`mouse-reporting = true` も戻した場合、CLI がマウス入力を取り込んでいるときにターミナル本来の選択をするには、Shift を押しながらドラッグしてください。

## Codex コマンド

アプリは Codex を次のように実行します:

```sh
codex exec --ignore-user-config --skip-git-repo-check --cd <application-support-workspace> --output-last-message <temp-file> -
```

`--ignore-user-config` は、`~/.codex/config.toml` の project エントリ（Downloads などの保護フォルダ配下のエントリを含む）を Codex が読まないようにするためのものです。`--cd` は SelectTranslate の Application Support 内の作業ディレクトリに固定しているので、アプリが現在のターミナルや Finder のディレクトリを使うことはありません。`--skip-git-repo-check` は、翻訳専用のこの作業ディレクトリで trusted directory のエラーが出ないようにするためのものです。

パネルで選んだ effort は次のように渡されます:

```sh
-c 'model_reasoning_effort="<effort>"'
```

設定画面で Codex のモデルを指定している場合は、次の引数も渡されます:

```sh
--model <model>
```

現在のショートカットセットのプロンプトテンプレートを展開し、stdin で `codex exec` に送ります。

### `~/.codex/config.toml` の設定を使う

`--ignore-user-config` を付けているため、デフォルトでは `~/.codex/config.toml` のカスタム `model_provider` などの設定は反映されません。ターミナルでは Codex が動くのに SelectTranslate では `401 Unauthorized` などのエラーになる場合は、`SelectTranslate` > `Settings...` > `Model` > `Codex` で次のどちらかを使ってください。

**Config overrides（推奨）**

1行に1つ `key=value` を書きます。各行は `-c key=value` として渡されます。空行と `#` で始まる行は無視されます。

```text
model_provider="my-provider"
model_providers.my-provider.name="my-provider"
model_providers.my-provider.base_url="https://example.com/v1"
```

`Import Current Config` を押すと、`~/.codex/config.toml`（`$CODEX_HOME` が設定されていれば `$CODEX_HOME/config.toml`）の内容を `key=value` の行に変換して、入力欄の内容を置き換えます:

- 各値は `tui.alternate_screen="never"` のようなドット区切りのキーで書き出されます。Codex は `-c` のキーを `.` ごとに区切り、引用符付きのキーを解釈しません。そのため、そうしたキーを含むテーブル（例: `[model_providers."my.provider"]`）は、親のパスに1つのインラインテーブルとしてまとめて書き出されます。
- `projects`、`mcp_servers`、`notify`、`plugins`、`marketplaces` は翻訳に不要なので、コメントアウトした行として取り込まれます。これらは信頼済みフォルダの一覧や、翻訳のたびに MCP サーバー・プラグイン・通知コマンドを起動する設定です。有効にしたい行は先頭の `#` を消してください。
- もう一度インポートすると、入力欄で編集した内容は上書きされます。

ユーザーの上書き設定は、アプリ自身の `model_reasoning_effort` より前に渡されます。そのため、パネルで選んだ `Effort` が優先されます。

**Load ~/.codex/config.toml**

有効にすると `--ignore-user-config` を付けずに実行するので、Codex は project エントリを含むユーザー設定全体を読み込みます。これらのエントリによって、Downloads などの保護フォルダへのアクセス許可ダイアログが macOS に表示されることがあるため、デフォルトではオフです。Config overrides はこの場合も上書きとして適用されます。

ユーザー設定に定義された MCP サーバーは、翻訳時には `-c mcp_servers.<name>.enabled=false` で無効にします。これは Config overrides より前に渡すので、上書き設定で明示的に有効にすることもできます。`-c mcp_servers={}` では設定済みのサーバーを取り除けません。そのため、名前に引用符が必要なサーバー（`-c` で指定できないもの）がある場合や、config を解析できない場合は、そのサーバーを有効にしたまま実行するのではなく、理由を表示して Codex での翻訳を失敗させます。このオプションがオンの間は、設定画面にも同じ警告を表示します。

**常に強制される設定**

選択テキストはプロンプトの一部として Codex に送られます。そのため、選択テキストによって Codex が読み取り専用を超える権限でコマンドを実行できないようにする必要があります。アプリは Config overrides の後に、常に次の引数を渡します:

```sh
--sandbox read-only -c 'approval_policy="never"'
```

これらはユーザー設定や Config overrides より優先されます。

## Claude コマンド

アプリは Claude を次のように実行します:

```sh
claude -p --safe-mode --no-session-persistence --output-format text --effort <effort>
```

設定画面で Claude のモデルを指定している場合は、次の引数も渡されます:

```sh
--model <model>
```

現在のショートカットセットのプロンプトテンプレートを展開し、stdin で `claude -p` に送ります。

## PLaMo コマンド

PLaMo エンジンは [`mlx-community/plamo-2-translate`](https://huggingface.co/mlx-community/plamo-2-translate) を使います。これは Apple Silicon 上の MLX 向けに 4bit 量子化された PLaMo 翻訳モデルです。使用前にモデルカードと PLaMo コミュニティライセンスを確認してください。

Built with PLaMo.

PLaMo のモデルは、このリポジトリにも `./scripts/build-app.sh` で作られるアプリにも同梱されていません。`Prepare PLaMo` を実行すると、アプリがローカルの Application Support ディレクトリにモデルをダウンロードします。PLaMo のモデルには SelectTranslate の Apache License 2.0 ではなく、PLaMo コミュニティライセンスが適用されます。商用利用には、Preferred Networks が定める追加の手続きが必要になる場合があります。

PLaMo エンジンを選ぶ前に、設定画面で `Prepare PLaMo` を実行してください。SelectTranslate はアプリ専用の Python 環境を作成し、`mlx-lm`、`numba`、`torch` をインストールして、モデルをダウンロードします。設定画面には、実行中のセットアップ手順とコマンドの出力（各ツールが報告するダウンロードの進捗を含む）がリアルタイムで表示されます。ファイルは次の場所に保存されます:

```sh
~/Library/Application Support/SelectTranslate/
```

旧名の CodexTranslator からアップグレードした場合、新しいディレクトリがまだなければ、既存の `~/Library/Application Support/CodexTranslator/` を `~/Library/Application Support/SelectTranslate/` に移動します。

手動でセットアップする場合は、次を実行します:

```sh
./scripts/install-plamo-deps.sh
```

セットアップ後、アプリは次のコマンドを実行します:

```sh
~/Library/Application\ Support/SelectTranslate/PLaMoEnvironment/bin/python3 -m mlx_lm generate --model mlx-community/plamo-2-translate --trust-remote-code --extra-eos-token '<|plamo:op|>' --max-tokens <dynamic limit> --prompt '<selected text>'
```

SelectTranslate は PLaMo の生成トークン上限を原文の長さから決めます。最小は 1024 トークン、最大は 8192 トークンです。これは、`mlx_lm generate` のデフォルトの上限では長い翻訳に足りないためです。

PLaMo は翻訳に特化したモデルで、チャット向けの instruction tuning はされていません。そのため、アプリは選択テキストをそのまま送ります。ショートカットのプロンプトテンプレートは Codex と API では使われますが、PLaMo では無視されます。

## Apple Foundation Models

`Apple` エンジンは、[Foundation Models フレームワーク](https://developer.apple.com/documentation/foundationmodels)を通じて Apple のオンデバイスのシステム言語モデルを使います。インストールは不要で、API キーや別途のモデルのダウンロードも必要ありません。

Apple Intelligence に対応した Mac の macOS 26 以降で、システム設定の Apple Intelligence がオンになっている必要があります。デバイスが対応していない場合、Apple Intelligence がオフの場合、モデルの準備ができていない場合（ダウンロード中など）は使えません。

アプリから Apple Intelligence をオンにしたり、モデルのダウンロードを始めたりすることはできません。Apple Intelligence がオフの間は、`SelectTranslate` > `Settings...` > `Model` の `Engine` の横に、`Prepare PLaMo` と同じように `Turn On Apple Intelligence` ボタンが表示されます。押すと システム設定 > Apple Intelligence と Siri が開きます。オンにすると、macOS がモデルをダウンロードします。SelectTranslate は、アプリがアクティブになったときと、待っている間は数秒ごとにモデルが使えるかを確認するので、アプリを再起動しなくても `Apple` エンジンを選べるようになります。

アプリは、現在のショートカットセットのプロンプトテンプレートを展開し、訳文だけを返すよう指示した新しい `LanguageModelSession` に送ります。返信の翻訳と返信の添削も同じエンジンで動きます。`Effort` の設定はこのエンジンには適用されません。

## OpenAI 互換 API

`API` エンジンは、OpenAI 互換の chat completions エンドポイントを呼び出します:

```sh
POST {base_url}/chat/completions
```

`SelectTranslate` > `Settings...` で次の値を設定します:

- `base_url`: `/v1` まで含めます。例: `http://localhost:1234/v1`
- `api_key`: 任意です。認証が不要なローカルサーバーでは空欄のままにします
- `model`: ローカル API が提供しているモデル名

リクエストには、翻訳結果だけを出力するよう指示する `system` メッセージと、現在のショートカットセットのプロンプトテンプレートを展開した `user` メッセージが含まれます。使うのは `/completions` ではなく `/chat/completions` です。

## ライセンス

SelectTranslate は Apache License 2.0 で公開しています。[LICENSE](LICENSE) を参照してください。

サードパーティのツール、Python パッケージ、モデルには、それぞれのライセンスと利用規約が適用されます。[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照してください。

ソースリポジトリと `./scripts/build-app.sh` で作られるアプリには、PLaMo のモデル、Python 環境、Python の wheel、Codex CLI は含まれていません。これらのいずれかを同梱したアプリを配布する場合は、同梱したバージョンに対応するライセンス本文と表示を含めてください。
