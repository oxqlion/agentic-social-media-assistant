"""Export Florence-2-base (encoder + decoder step) to Core AI (.aimodel), fp16, and check parity.

Same wrappers as export_clip_and_florence2.ipynb, so the only variable vs. the
Core ML export is the runtime: the encoder bakes the "<CAPTION>" task prompt in;
the decoder step has NO KV cache and recomputes the full fixed-length
(MAX_CAPTION_TOKENS) prefix each call. Inputs/outputs are float32/int32 at the
boundary; weights are fp16.

Encoder input `pixel_values`: float32 [1,3,768,768] RGB in 0..255 (mean/std baked in).
Decoder inputs: `decoder_input_ids` int32 [1,40], `encoder_hidden_states` float32 [1,N,768].
"""

import argparse
from pathlib import Path

import numpy as np
import torch
from PIL import Image
from transformers import AutoModelForCausalLM, AutoProcessor

import coreai_common as cc

MODEL_ID = "microsoft/Florence-2-base"
TASK_PROMPT = "<CAPTION>"
MAX_CAPTION_TOKENS = 40


class FlorenceEncoder(torch.nn.Module):
    def __init__(self, model, task_input_ids, mean, std):
        super().__init__()
        self.model = model
        self.register_buffer("task_input_ids", task_input_ids)
        self.register_buffer("mean", torch.tensor(mean).view(1, 3, 1, 1) * 255.0)
        self.register_buffer("std", torch.tensor(std).view(1, 3, 1, 1) * 255.0)

    def forward(self, pixel_values):
        dtype = self.model.get_input_embeddings().weight.dtype
        x = ((pixel_values - self.mean) / self.std).to(dtype)
        image_features = self.model._encode_image(x)
        task_prefix_embeds = self.model.get_input_embeddings()(self.task_input_ids)
        merged_embeds, merged_attention_mask = self.model._merge_input_ids_with_image_features(
            image_features, task_prefix_embeds
        )
        out = self.model.language_model.get_encoder()(
            inputs_embeds=merged_embeds, attention_mask=merged_attention_mask, return_dict=True
        ).last_hidden_state
        return out.float()


class FlorenceDecoderStep(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.decoder = model.language_model.get_decoder()
        self.lm_head = model.language_model.lm_head
        self.register_buffer("final_logits_bias", model.language_model.final_logits_bias)

    def forward(self, decoder_input_ids, encoder_hidden_states):
        dtype = self.lm_head.weight.dtype
        decoder_out = self.decoder(
            input_ids=decoder_input_ids.to(torch.int64),
            encoder_hidden_states=encoder_hidden_states.to(dtype),
            past_key_values=None,
            use_cache=False,
            return_dict=True,
        )
        return (self.lm_head(decoder_out.last_hidden_state) + self.final_logits_bias).float()


class _TorchNoInfNanCheck:
    """`torch` as seen by Florence's remote modeling code, with isinf/isnan constant-False.

    Its fp16 encoder layers do `if isinf(x).any() or isnan(x).any(): clamp(...)`, a
    data-dependent branch torch.export can't trace. The clamp only matters if
    activations already overflowed; parity in this script checks that they don't.
    """

    def __getattr__(self, name):
        return getattr(torch, name)

    class _Never:
        @staticmethod
        def any():
            return False

    @staticmethod
    def isinf(x):
        return _TorchNoInfNanCheck._Never()

    isnan = isinf


def load(dtype):
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_ID, trust_remote_code=True, attn_implementation="eager", torch_dtype=dtype
    ).eval()
    if dtype == torch.float16:
        import sys
        sys.modules[type(model.language_model).__module__].torch = _TorchNoInfNanCheck()
    for p in model.parameters():
        p.requires_grad_(False)
    return model


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=cc.HERE / "exported_models")
    ap.add_argument("--images", type=Path, required=True)
    args = ap.parse_args()

    proc = AutoProcessor.from_pretrained(MODEL_ID, trust_remote_code=True)
    mapped = proc._construct_prompts([TASK_PROMPT])[0]
    task_ids = proc.tokenizer(text=mapped, return_tensors="pt")["input_ids"]
    size = proc.image_processor.size["height"]
    mean, std = proc.image_processor.image_mean, proc.image_processor.image_std

    fp32 = load(torch.float32)
    text_cfg = fp32.config.text_config
    start_id, pad_id, eos_id = text_cfg.decoder_start_token_id, text_cfg.pad_token_id, text_cfg.eos_token_id

    paths = sorted(args.images.glob("*.JPG"))[:2]
    pixels = [
        torch.from_numpy(np.asarray(Image.open(p).convert("RGB").resize((size, size), Image.BICUBIC), dtype=np.float32))
        .permute(2, 0, 1).unsqueeze(0).contiguous()
        for p in paths
    ]

    ref_enc, ref_dec = FlorenceEncoder(fp32, task_ids, mean, std).eval(), FlorenceDecoderStep(fp32).eval()
    with torch.no_grad():
        hidden = [ref_enc(px) for px in pixels]
        # Greedy reference caption with the fp32 decoder step, to get a realistic prefix + its logits.
        prefixes, logits = [], []
        for h in hidden:
            ids = torch.full((1, MAX_CAPTION_TOKENS), pad_id, dtype=torch.int32)
            ids[0, 0] = start_id
            n = 1
            for _ in range(MAX_CAPTION_TOKENS - 1):
                nxt = int(ref_dec(ids, h)[0, n - 1].argmax())
                ids[0, n] = nxt
                n += 1
                if nxt == eos_id:
                    break
            prefixes.append((ids.clone(), n))
            logits.append(ref_dec(ids, h))
    for (ids, n), p in zip(prefixes, paths):
        print(f"{p.name}: {proc.tokenizer.decode(ids[0, :n].tolist(), skip_special_tokens=True)!r}")

    fp16 = load(torch.float16)
    enc16, dec16 = FlorenceEncoder(fp16, task_ids, mean, std).eval(), FlorenceDecoderStep(fp16).eval()

    enc_path, dec_path = args.out / "FlorenceEncoder.aimodel", args.out / "FlorenceDecoderStep.aimodel"
    cc.convert(enc16, (pixels[0],), ["pixel_values"], ["encoder_hidden_states"], enc_path)
    cc.convert(dec16, (prefixes[0][0], hidden[0]), ["decoder_input_ids", "encoder_hidden_states"], ["logits"], dec_path)

    spec = args.out / "florence_encoder_parity.json"
    cc.write_parity_spec(spec, enc_path, [{"inputs": {"pixel_values": px}, "outputs": {"encoder_hidden_states": h}} for px, h in zip(pixels, hidden)])
    cc.run_parity(spec)

    spec = args.out / "florence_decoder_parity.json"
    cc.write_parity_spec(spec, dec_path, [
        {"inputs": {"decoder_input_ids": ids, "encoder_hidden_states": h}, "outputs": {"logits": lg}}
        for (ids, _), h, lg in zip(prefixes, hidden, logits)
    ], argmax_rows=min(n for _, n in prefixes))
    cc.run_parity(spec)


if __name__ == "__main__":
    main()
