"""Shared helpers for the Core AI (`.aimodel`) exports in this folder.

Each export_*_coreai.py builds a wrapper module, calls `convert(...)`, then
`write_parity_spec(...)`; `run_parity(...)` executes the exported model through
the real Core AI Swift runtime on this Mac (parity_check.swift) and prints
cosine similarity against the PyTorch fp32 reference.
"""

import json
import subprocess
from pathlib import Path

import numpy as np
import torch

import coreai_torch

HERE = Path(__file__).parent


def convert(module, args, input_names, output_names, out_path, *, dynamic_shapes=None):
    """torch.export -> Core AI program -> `<out_path>` (.aimodel)."""
    exported = torch.export.export(module, args=args, dynamic_shapes=dynamic_shapes)
    exported = exported.run_decompositions(coreai_torch.get_decomp_table())
    program = (
        coreai_torch.TorchConverter()
        .add_exported_program(exported, input_names=input_names, output_names=output_names)
        .to_coreai()
    )
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    program.save_asset(out_path)
    size_mb = sum(f.stat().st_size for f in out_path.rglob("*") if f.is_file()) / 1e6
    print(f"saved {out_path} ({size_mb:.1f} MB)")
    return exported


def tensor_spec(t, argmax_rows=None):
    a = t.detach().cpu().numpy()
    dtype = {"int32": "int32", "float32": "float32"}[str(a.dtype)]
    spec = {"dtype": dtype, "shape": list(a.shape), "data": a.ravel().tolist()}
    if argmax_rows is not None:
        spec["argmaxRows"] = argmax_rows
    return spec


def write_parity_spec(path, model_path, cases, argmax_rows=None):
    """cases: [{"inputs": {name: tensor}, "outputs": {name: tensor}}] (torch fp32 reference)."""
    spec = {
        "model": str(model_path),
        "cases": [
            {
                "inputs": {k: tensor_spec(v) for k, v in c["inputs"].items()},
                "outputs": {k: tensor_spec(v.float(), argmax_rows) for k, v in c["outputs"].items()},
            }
            for c in cases
        ],
    }
    Path(path).write_text(json.dumps(spec))


def run_parity(spec_path):
    src = HERE / "parity_check.swift"
    build = Path(spec_path).parent / "parity_bin"
    build.mkdir(exist_ok=True)
    main = build / "main.swift"
    main.write_text(src.read_text())
    exe = build / "parity"
    subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-o", str(exe), str(main)], check=True)
    subprocess.run([str(exe), str(spec_path)], check=True)


def cosine(a, b):
    a, b = np.asarray(a, dtype=np.float64).ravel(), np.asarray(b, dtype=np.float64).ravel()
    return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)))
