"""Export the CLAP text encoder to Core AI (.aimodel) and check parity.

fp32, like the Core ML export: fp16 was measured unsafe for RoBERTa here
(cosine 0.02-0.19, see export_clap.ipynb). Batch 1, fixed sequence length 64.
"""

import argparse
from pathlib import Path

import torch
from transformers import ClapModel, ClapProcessor

import coreai_common as cc

MODEL_ID = "laion/clap-htsat-unfused"
TEXT_SEQ_LEN = 64


class ClapTextEncoderExport(torch.nn.Module):
    def __init__(self, clap):
        super().__init__()
        self.text_model = clap.text_model
        self.text_projection = clap.text_projection

    def forward(self, input_ids, attention_mask):
        out = self.text_model(input_ids=input_ids, attention_mask=attention_mask, return_dict=True)
        feats = self.text_projection(out.pooler_output)
        return feats / feats.norm(p=2, dim=-1, keepdim=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=cc.HERE / "exported_models")
    args = ap.parse_args()

    clap = ClapModel.from_pretrained(MODEL_ID).eval()
    for p in clap.parameters():
        p.requires_grad_(False)
    proc = ClapProcessor.from_pretrained(MODEL_ID)
    queries = [
        "an upbeat, danceable pop song",
        "a slow, emotional piano ballad",
        "a relaxing acoustic guitar tune",
        "a high-energy rock anthem",
    ]
    toks = proc.tokenizer(queries, padding="max_length", max_length=TEXT_SEQ_LEN, truncation=True, return_tensors="pt")
    ids, mask = toks["input_ids"].to(torch.int32), toks["attention_mask"].to(torch.int32)

    model = ClapTextEncoderExport(clap).eval()
    with torch.no_grad():
        refs = [model(ids[i:i + 1], mask[i:i + 1]) for i in range(len(queries))]

    out_path = args.out / "ClapTextEncoder.aimodel"
    cc.convert(model, (ids[:1], mask[:1]), ["input_ids", "attention_mask"], ["text_embeds"], out_path)

    spec = args.out / "clap_text_parity.json"
    cc.write_parity_spec(spec, out_path, [
        {"inputs": {"input_ids": ids[i:i + 1], "attention_mask": mask[i:i + 1]}, "outputs": {"text_embeds": refs[i]}}
        for i in range(len(queries))
    ])
    cc.run_parity(spec)


if __name__ == "__main__":
    main()
