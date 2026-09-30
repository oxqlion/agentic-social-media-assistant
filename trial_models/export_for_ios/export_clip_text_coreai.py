"""Export the CLIP text encoder to a Core AI `.aimodel` and check parity.

Mirrors ClipTextEncoder in export_clip_and_florence2.ipynb (same wrapper,
same fp16-safe additive masks, same EOS one-hot pooling) so the only variable
vs. the Core ML export is the runtime/format. Batch is 1 (the Core ML export
was frozen at 3 and the app tiled a single query across the rows).

Setup (isolated env; needs Python 3.12):
    uv venv --python 3.12 .venv-coreai && source .venv-coreai/bin/activate
    uv pip install coreai-torch "transformers==4.51.3" coremltools pillow sentencepiece protobuf

Run:
    python export_clip_text_coreai.py [--out exported_models] [--coreml path/to/CLIPTextEncoder.mlpackage]
"""

import argparse
from pathlib import Path

import numpy as np
import torch
from transformers import CLIPModel, CLIPTokenizer

import coreai_torch

MODEL_ID = "openai/clip-vit-base-patch32"
NEG_INF = -1e4  # fp16-safe stand-in for -inf in additive attention masks


class ClipTextEncoder(torch.nn.Module):
    def __init__(self, clip, seq_len):
        super().__init__()
        text_model = clip.text_model
        self.embeddings = text_model.embeddings
        self.encoder = text_model.encoder
        self.final_layer_norm = text_model.final_layer_norm
        self.text_projection = clip.text_projection

        causal_mask = torch.triu(torch.full((seq_len, seq_len), NEG_INF), diagonal=1)
        self.register_buffer("causal_mask", causal_mask.unsqueeze(0).unsqueeze(0))
        self.seq_len = seq_len

    def forward(self, input_ids, attention_mask):
        hidden_states = self.embeddings(input_ids=input_ids)

        padding_mask = (1.0 - attention_mask[:, None, None, :].to(hidden_states.dtype)) * NEG_INF
        combined_mask = self.causal_mask + padding_mask

        encoder_outputs = self.encoder(
            inputs_embeds=hidden_states, attention_mask=combined_mask, causal_attention_mask=None
        )
        last_hidden_state = self.final_layer_norm(encoder_outputs.last_hidden_state)

        # EOS pooling via one-hot contraction instead of fancy indexing.
        eos_idx = input_ids.to(dtype=torch.int64).argmax(dim=-1)
        positions = torch.arange(self.seq_len, device=last_hidden_state.device).unsqueeze(0)
        one_hot = (positions == eos_idx.unsqueeze(1)).to(last_hidden_state.dtype)
        pooled_output = torch.einsum("bs,bsd->bd", one_hot, last_hidden_state)

        text_embeds = self.text_projection(pooled_output)
        return text_embeds / text_embeds.norm(p=2, dim=-1, keepdim=True)


def cosine(a, b):
    a, b = np.asarray(a, dtype=np.float64).ravel(), np.asarray(b, dtype=np.float64).ravel()
    return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path(__file__).parent / "exported_models")
    parser.add_argument("--fp32", action="store_true", help="keep fp32 weights (default: fp16, matching the Core ML export)")
    parser.add_argument("--coreml", type=Path, default=None, help="existing CLIPTextEncoder.mlpackage to compare against")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    clip = CLIPModel.from_pretrained(MODEL_ID).eval()
    for p in clip.parameters():
        p.requires_grad_(False)
    tokenizer = CLIPTokenizer.from_pretrained(MODEL_ID)
    seq_len = clip.config.text_config.max_position_embeddings  # 77

    encoder = ClipTextEncoder(clip, seq_len).eval()
    texts = ["a photo of a person", "a photo of food", "a photo of a landscape or building"]
    toks = tokenizer(texts, padding="max_length", max_length=seq_len, truncation=True, return_tensors="pt")
    example_ids = toks["input_ids"][:1].to(torch.int32)
    example_mask = toks["attention_mask"][:1].to(torch.int32)

    ref_encoder = encoder
    if not args.fp32:
        encoder = ClipTextEncoder(clip, seq_len).eval().half()
    exported = torch.export.export(encoder, args=(example_ids, example_mask))
    exported = exported.run_decompositions(coreai_torch.get_decomp_table())
    program = (
        coreai_torch.TorchConverter()
        .add_exported_program(exported, input_names=["input_ids", "attention_mask"], output_names=["text_embeds"])
        .to_coreai()
    )
    aimodel_path = args.out / "CLIPTextEncoder.aimodel"
    program.save_asset(aimodel_path)
    print(f"saved {aimodel_path}")

    # Parity: exported program (fp32, PyTorch semantics) vs the original module, and vs Core ML if given.
    with torch.no_grad():
        ref = ref_encoder(toks["input_ids"].to(torch.int32), toks["attention_mask"].to(torch.int32)).numpy()
        exported_out = exported.module()(example_ids, example_mask).float().numpy()
    print(f"exported-program vs fp32 module cosine: {cosine(ref[0], exported_out[0]):.6f}")

    if args.coreml:
        import coremltools as ct

        mlmodel = ct.models.MLModel(str(args.coreml))
        out = mlmodel.predict({
            "input_ids": toks["input_ids"].numpy().astype(np.int32),
            "attention_mask": toks["attention_mask"].numpy().astype(np.int32),
        })["text_embeds"]
        for text, r, c in zip(texts, ref, out):
            print(f"Core ML fp16 vs PyTorch fp32  {text!r:38s} {cosine(r, c):.5f}")


if __name__ == "__main__":
    main()
