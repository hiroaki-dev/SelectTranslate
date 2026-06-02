# Third-Party Notices

SelectTranslate does not vendor third-party Swift packages, Python packages, model
weights, or the Codex CLI in this source repository.

The app can call external tools and install runtime dependencies into the user's
local Application Support directory when the user chooses those engines. Those
components remain governed by their own licenses and terms.

## External tools and runtime packages

| Component | Role | License / terms |
| --- | --- | --- |
| OpenAI Codex CLI | Optional `codex exec` translation engine. The CLI is not bundled with this app. | Apache-2.0 |
| mlx-lm | Installed by `Prepare PLaMo` to run MLX language models. | MIT |
| MLX | Runtime dependency of `mlx-lm`. | MIT |
| numba | Installed by `Prepare PLaMo`. | BSD-2-Clause |
| torch / PyTorch | Installed by `Prepare PLaMo` for PLaMo model remote code dependencies. | BSD-style license |
| Hugging Face Transformers | Installed transitively by `mlx-lm`; used for tokenizer/model loading. | Apache-2.0 |
| huggingface_hub | Installed transitively by `mlx-lm`; used to download model files. | Apache-2.0 |
| tokenizers | Installed transitively by Transformers. | Apache-2.0 |

If you distribute a packaged app that bundles any Python environment, wheels,
model files, or CLI binaries, include the corresponding license texts and notices
for the bundled versions.

## PLaMo model

Built with PLaMo.

The PLaMo engine downloads and runs `mlx-community/plamo-2-translate` from
Hugging Face. The model is released under the PLaMo community license, not under
SelectTranslate's Apache License 2.0. Users must review and comply with the PLaMo
community license before downloading or using the model.

Commercial use of the PLaMo model may require additional steps described by
Preferred Networks, including registration or contacting Preferred Networks.

Links:

- https://huggingface.co/mlx-community/plamo-2-translate
- https://www.preferred.jp/ja/plamo-community-license/
