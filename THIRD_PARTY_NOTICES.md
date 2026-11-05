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
| mlx-lm | Installed by the first PLaMo download to run MLX language models. | MIT |
| MLX | Installed by the first PLaMo download; runtime dependency of `mlx-lm`. | MIT |
| numba | Installed by the first PLaMo download for PLaMo model remote code dependencies. | BSD-2-Clause |
| Hugging Face Transformers | Installed by the first PLaMo download; used for tokenizer/model loading. | Apache-2.0 |
| huggingface_hub | Installed transitively by `mlx-lm`; used to download model files. | Apache-2.0 |
| tokenizers | Installed transitively by Transformers. | Apache-2.0 |

If you distribute a packaged app that bundles any Python environment, wheels,
model files, or CLI binaries, include the corresponding license texts and notices
for the bundled versions.

## PLaMo model

Built with PLaMo.

The PLaMo engine downloads and runs the PLaMo 3 Translate MLX 4-bit models
(`pfnet/plamo-3-translate-{0.8b,2b,8b,31b}-MLX-4bit`) from Hugging Face. The
models are released under the PLaMo Community License, not under SelectTranslate's
Apache License 2.0. Users must review and comply with the PLaMo Community License
before downloading or using the models.

Commercial use of the PLaMo model may require additional steps described by
Preferred Networks, including registration or contacting Preferred Networks.

Links:

- https://huggingface.co/pfnet/plamo-3-translate-0.8b-MLX-4bit
- https://huggingface.co/pfnet/plamo-3-translate-2b-MLX-4bit
- https://huggingface.co/pfnet/plamo-3-translate-8b-MLX-4bit
- https://huggingface.co/pfnet/plamo-3-translate-31b-MLX-4bit
- https://plamo.preferredai.jp/info/plamo-community-license-en
