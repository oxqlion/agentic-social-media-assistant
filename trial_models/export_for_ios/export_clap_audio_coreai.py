"""Export the CLAP (HTSAT) audio encoder to Core AI (.aimodel), fp32, and check parity.

Input `waveform` is float32 [1, 480000] (10 s mono @ 48 kHz), same as the Core
ML export; the Conv1d-STFT + mel front end and L2-normalized 512-d output match
export_clap.ipynb. fp32 because fp16 was measured unsafe for CLAP there.

The Core ML export needed HTSAT patched (literal shapes, bicubic-as-matmul).
Pass --patched to reuse those patches from the notebook if plain torch.export
of the stock model fails.
"""

import argparse
import json
from pathlib import Path

import librosa
import numpy as np
import torch
import torch.nn as nn
from transformers import ClapModel, ClapProcessor
from transformers.audio_utils import window_function

import coreai_common as cc

MODEL_ID = "laion/clap-htsat-unfused"
SR, WINDOW_S = 48000, 10
SAMPLES = SR * WINDOW_S


def notebook_cells(nb_path, indices):
    nb = json.loads(Path(nb_path).read_text())
    return "\n".join("".join(nb["cells"][i]["source"]) for i in indices)


class ClapAudioEncoderExport(nn.Module):
    def __init__(self, clap, cos_basis, sin_basis, mel_filters, n_fft, hop):
        super().__init__()
        self.audio_encoder = clap.audio_model.audio_encoder
        self.audio_projection = clap.audio_projection
        self.register_buffer("cos_w", torch.tensor(cos_basis).unsqueeze(1))
        self.register_buffer("sin_w", torch.tensor(sin_basis).unsqueeze(1))
        self.register_buffer("mel_filters_t", torch.tensor(mel_filters))
        self.n_fft, self.hop = n_fft, hop

    def forward(self, waveform):
        x = waveform.unsqueeze(1)
        pad = self.n_fft // 2
        x = nn.functional.pad(x, (pad, pad), mode="reflect")
        real = nn.functional.conv1d(x, self.cos_w, stride=self.hop)
        imag = nn.functional.conv1d(x, self.sin_w, stride=self.hop)
        power = real**2 + imag**2
        mel = torch.clamp(torch.einsum("fm,bft->bmt", self.mel_filters_t, power), min=1e-10)
        log_mel = 10.0 * torch.log10(mel)
        input_features = log_mel.transpose(1, 2).unsqueeze(1)
        pooled = self.audio_encoder(input_features=input_features, is_longer=None)
        pooled = getattr(pooled, "pooler_output", pooled)  # stock HTSAT returns an output object, the patched one a tensor
        embeds = self.audio_projection(pooled)
        return embeds / embeds.norm(p=2, dim=-1, keepdim=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=cc.HERE / "exported_models")
    ap.add_argument("--audios", type=Path, default=cc.HERE.parent / "audios")
    ap.add_argument("--patched", action="store_true")
    ap.add_argument("--notebook", type=Path, default=cc.HERE / "export_clap.ipynb")
    args = ap.parse_args()

    clap = ClapModel.from_pretrained(MODEL_ID).eval()
    for p in clap.parameters():
        p.requires_grad_(False)
    proc = ClapProcessor.from_pretrained(MODEL_ID)
    fe = proc.feature_extractor
    n_fft, hop = fe.fft_window_size, fe.hop_length

    hann = window_function(n_fft, "hann").astype(np.float64)
    angle = 2 * np.pi * np.outer(np.arange(n_fft // 2 + 1), np.arange(n_fft)) / n_fft
    cos_basis = (np.cos(angle) * hann[None, :]).astype(np.float32)
    sin_basis = (-np.sin(angle) * hann[None, :]).astype(np.float32)
    mel_filters = fe.mel_filters_slaney.astype(np.float32)

    if args.patched:
        # Notebook cells: 7 = bicubic-as-matmul matrix, 9 = HTSAT patches (defines apply_clap_audio_coreml_patches).
        g = {"torch": torch, "nn": nn, "np": np, "clap_model": clap, "audio_config": clap.config.audio_config, "SR": SR}
        exec(notebook_cells(args.notebook, [7, 9]), g)
        g["apply_clap_audio_coreml_patches"](clap, g["time_interp_matrix"])

    model = ClapAudioEncoderExport(clap, cos_basis, sin_basis, mel_filters, n_fft, hop).eval()

    waves = []
    for path in sorted(args.audios.glob("*.mp3"))[:3]:
        w, _ = librosa.load(path, sr=SR, mono=True, duration=WINDOW_S)
        w = np.pad(w[:SAMPLES], (0, max(0, SAMPLES - len(w[:SAMPLES])))).astype(np.float32)
        waves.append(torch.from_numpy(w).unsqueeze(0))
    with torch.no_grad():
        refs = [model(w) for w in waves]

    out_path = args.out / "ClapAudioEncoder.aimodel"
    cc.convert(model, (waves[0],), ["waveform"], ["audio_embeds"], out_path)

    spec = args.out / "clap_audio_parity.json"
    cc.write_parity_spec(spec, out_path, [
        {"inputs": {"waveform": w}, "outputs": {"audio_embeds": r}} for w, r in zip(waves, refs)
    ])
    cc.run_parity(spec)


if __name__ == "__main__":
    main()
