#!/usr/bin/env python3
"""Summarize product-hardware qualification reports under a directory tree."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    args = sys.argv[1:]
    command = [
        sys.executable,
        str(ROOT / "scripts" / "product_qualification.py"),
        "summarize",
    ]
    if not args or args[0] != "--input":
        print("Usage: summarize-product-qualification.py --input PATH [--output PATH]", file=sys.stderr)
        return 2
    command.extend(args)
    return subprocess.call(command)


if __name__ == "__main__":
    raise SystemExit(main())
