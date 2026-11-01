#!/usr/bin/env python3
"""Draws Klieg's animated SVGs into docs/images. Standard library only.

    python3 scripts/make-visuals.py            # all visuals
    python3 scripts/make-visuals.py hero board # just these modules

Each module in scripts/visuals/ (other than common.py) has a build() returning {"file.svg": text}.
"""
import importlib
import os
import pkgutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "docs", "images")
sys.path.insert(0, HERE)

import visuals  # noqa: E402

wanted = set(sys.argv[1:])
os.makedirs(OUT, exist_ok=True)
for mod in sorted(m.name for m in pkgutil.iter_modules(visuals.__path__)):
    if mod == "common" or (wanted and mod not in wanted):
        continue
    for name, text in importlib.import_module(f"visuals.{mod}").build().items():
        with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
            f.write(text)
        print(f"  {name}  ({len(text) // 1024} KB)  from visuals/{mod}.py")
