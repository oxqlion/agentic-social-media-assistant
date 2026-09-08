# app-v1

An agentic AI iOS app with on-device CLIP-based image retrieval. This repo has two parts:

```
app-v1/
├── app-v1/         # iOS app (SwiftUI, Xcode project)
└── trial_models/   # Python experiments for the AI model used by the app
```

## `app-v1/` — iOS app

SwiftUI project (`app-v1.xcodeproj`) implementing the agentic flow:

- `Models/AgentFlowModel.swift` — agent flow state/logic
- `Views/ImageSelectorView.swift` — pick input image(s)
- `Views/PromptInputView.swift` — enter a prompt
- `Views/AgentProgressView.swift` — show agent progress
- `Views/ResultView.swift` — display results

Open `app-v1.xcodeproj` in Xcode to build and run.

### Setup

The Hashtag Agent's web search tool calls [Serper](https://serper.dev). Copy
the secrets template and fill in your API key before building:

```bash
cp app-v1/Secrets.example.swift app-v1/app-v1/Config/Secrets.swift
# then edit app-v1/app-v1/Config/Secrets.swift with your Serper API key
```

`Config/Secrets.swift` is gitignored, so your key never lands in source control.

## `trial_models/` — AI model experiments

CLIP model benchmarking for iOS image retrieval. This is where candidate models are evaluated before being exported for on-device use in the iOS app.

- `notebooks/benchmark_clip_models.ipynb` — compares CLIP model variants
- `notebooks/multi_image_summary.ipynb` — multi-image summarization experiments
- `images/` — sample images used for benchmarking/testing
- `pyproject.toml` / `uv.lock` — dependencies, managed with [uv](https://docs.astral.sh/uv/)

### Setup

```bash
cd trial_models
uv sync
uv run jupyter lab
```

### Plan

Evaluate and select a CLIP model here, then export/convert it (e.g. to Core ML) for local, on-device inference in the `app-v1` iOS app — no server round-trip required.
