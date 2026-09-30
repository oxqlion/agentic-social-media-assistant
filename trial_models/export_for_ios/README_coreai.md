# Core AI (`.aimodel`) exports

PyTorch -> `torch.export` -> `coreai-torch` -> `.aimodel`. Each script exports one
model, then runs the exported model through the real Core AI Swift runtime on the
Mac (`parity_check.swift`) and prints cosine vs. the PyTorch fp32 reference.

Setup (Python 3.12, isolated env):

    uv venv --python 3.12 .venv-coreai && source .venv-coreai/bin/activate
    uv pip install coreai-torch "transformers==4.51.3" coremltools pillow sentencepiece protobuf librosa soundfile einops timm

| Script | Model | Precision | Notes |
|---|---|---|---|
| export_clip_text_coreai.py | CLIPTextEncoder | fp16 | batch 1 (Core ML export was frozen at 3) |
| export_clip_image_coreai.py | CLIPImageEncoder | fp16 | input float32 [1,3,224,224] RGB 0..255, mean/std baked in |
| export_clap_text_coreai.py | ClapTextEncoder | fp32 | fp16 unsafe for RoBERTa (see export_clap.ipynb) |
| export_clap_audio_coreai.py | ClapAudioEncoder | fp32 | stock HTSAT exports; the Core ML patches are not needed (`--patched` keeps them available) |
| export_florence_coreai.py | FlorenceEncoder + FlorenceDecoderStep | fp16 | same no-KV-cache decoder as Core ML; shims Florence's fp16 isinf/isnan clamp |

Copy the resulting `*.aimodel` into `app-v1/app-v1/CoreAIModels/`. Turn the runtime on with
the launch argument `-os27UseCoreAI YES`, or for the UI test `TEST_RUNNER_OS27_USE_COREAI=1`.

Core AI is device-only: the iOS Simulator SDK has no CoreAI framework, and the build needs
the Metal Toolchain (`xcodebuild -downloadComponent metalToolchain`).
