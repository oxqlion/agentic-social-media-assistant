"""Export the CLIP image encoder to Core AI (.aimodel), fp16, and check parity.

Input `pixel_values` is float32 [1,3,224,224] RGB in 0..255 (already
resized/center-cropped by the app); mean/std normalization is baked into the
model, replacing Core ML's ImageType scale/bias. Output `image_embeds` is
L2-normalized, like the Core ML export.

    python export_clip_image_coreai.py --out exported_models --images ../../../case-study/fixtures/photos
"""

import argparse
from pathlib import Path

import numpy as np
import torch
from PIL import Image
from transformers import CLIPModel, CLIPProcessor

import coreai_common as cc

MODEL_ID = "openai/clip-vit-base-patch32"


class ClipImageEncoder(torch.nn.Module):
    def __init__(self, clip, mean, std):
        super().__init__()
        self.clip = clip
        self.register_buffer("mean", torch.tensor(mean).view(1, 3, 1, 1) * 255.0)
        self.register_buffer("std", torch.tensor(std).view(1, 3, 1, 1) * 255.0)

    def forward(self, pixel_values):
        dtype = self.clip.vision_model.embeddings.patch_embedding.weight.dtype
        x = ((pixel_values - self.mean) / self.std).to(dtype)
        feats = self.clip.get_image_features(pixel_values=x)
        feats = feats.float()
        return feats / feats.norm(p=2, dim=-1, keepdim=True)


def preprocess_0_255(img, size):
    """Shortest-edge resize + center crop (same as the app's aspectFillCenterCrop) -> float32 [1,3,S,S] in 0..255."""
    w, h = img.size
    scale = size / min(w, h)
    nw, nh = round(w * scale), round(h * scale)
    img = img.resize((nw, nh), Image.BICUBIC)
    l, t = (nw - size) // 2, (nh - size) // 2
    img = img.crop((l, t, l + size, t + size))
    return torch.from_numpy(np.asarray(img, dtype=np.float32)).permute(2, 0, 1).unsqueeze(0).contiguous()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=cc.HERE / "exported_models")
    ap.add_argument("--images", type=Path, required=True)
    ap.add_argument("--fp32", action="store_true")
    args = ap.parse_args()

    clip = CLIPModel.from_pretrained(MODEL_ID).eval()
    for p in clip.parameters():
        p.requires_grad_(False)
    proc = CLIPProcessor.from_pretrained(MODEL_ID)
    size = clip.config.vision_config.image_size
    mean, std = proc.image_processor.image_mean, proc.image_processor.image_std

    ref_model = ClipImageEncoder(clip, mean, std).eval()
    paths = sorted(args.images.glob("*.JPG"))[:3]
    tensors = [preprocess_0_255(Image.open(p).convert("RGB"), size) for p in paths]
    with torch.no_grad():
        refs = [ref_model(t) for t in tensors]

    model = ref_model if args.fp32 else ClipImageEncoder(CLIPModel.from_pretrained(MODEL_ID).eval().half(), mean, std).eval()
    out_path = args.out / "CLIPImageEncoder.aimodel"
    cc.convert(model, (tensors[0],), ["pixel_values"], ["image_embeds"], out_path)

    spec = args.out / "clip_image_parity.json"
    cc.write_parity_spec(spec, out_path, [
        {"inputs": {"pixel_values": t}, "outputs": {"image_embeds": r}} for t, r in zip(tensors, refs)
    ])
    cc.run_parity(spec)


if __name__ == "__main__":
    main()
