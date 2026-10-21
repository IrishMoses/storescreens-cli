#!/usr/bin/env python3
"""Write a Koubou framing configuration for one simulator's captured PNGs.

This example only connects files. Koubou supplies the frames and rendering.
Review or replace the generated layout before using it for a store submission.
"""
import argparse
import json
import os
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("manifest", type=Path)
parser.add_argument("--simulator", required=True)
parser.add_argument("--frame", required=True, help="Exact name from kou list-frames")
parser.add_argument("--size", required=True, help="Output size from kou list-sizes")
parser.add_argument("--config", type=Path, required=True)
parser.add_argument("--output-dir", type=Path, required=True)
args = parser.parse_args()
manifest = json.loads(args.manifest.read_text())
config_dir = args.config.resolve().parent
screenshots = {}
for device in manifest["devices"]:
    if device["simulatorName"] != args.simulator:
        continue
    for shot in device["screenshots"]:
        source = (args.manifest.resolve().parent / shot["filename"]).resolve()
        if not source.is_file():
            raise FileNotFoundError(source)
        name = "_".join([device.get("locale") or "default", device.get("appearance") or "default", shot["name"]])
        key = re.sub(r"[^A-Za-z0-9_-]", "_", name)
        if key in screenshots:
            raise ValueError(f"Duplicate screenshot key: {key}")
        screenshots[key] = {"content": [{"type": "image", "asset": os.path.relpath(source, config_dir),
                                        "frame": True, "position": ["50%", "50%"], "scale": 0.75}]}
if not screenshots:
    raise ValueError(f"No captures for {args.simulator!r}")
config = {
    "project": {"name": "StoreScreens capture example", "device": args.frame,
                "output_size": args.size, "output_dir": os.path.relpath(args.output_dir.resolve(), config_dir)},
    "defaults": {"background": {"type": "solid", "colors": ["#f0f0e6"]}},
    "screenshots": screenshots,
}
config_dir.mkdir(parents=True, exist_ok=True)
args.config.write_text(json.dumps(config, indent=2) + "\n")
print(f"Wrote {len(screenshots)} images to {args.config}. Render with: kou generate {args.config}")
