#!/usr/bin/env python3
"""Expand Pascal {$include ...} directives for source inspection."""

from __future__ import annotations

import argparse
from pathlib import Path


def include_name(line: str) -> str | None:
    stripped = line.strip()
    lower = stripped.lower()
    if not (lower.startswith("{$include ") or lower.startswith("{$i ")):
        return None
    parts = stripped.split(None, 1)
    if len(parts) != 2:
        return None
    return parts[1].replace("}", "").replace("'", "").replace('"', "").strip()


def expand(path: Path, base_dir: Path) -> list[str]:
    result: list[str] = []
    for line in path.read_text().splitlines():
        inc = include_name(line)
        if inc is None:
            result.append(line)
        else:
            result.extend(expand(base_dir / inc, base_dir))
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", nargs="?", default="compiler/compiler.pas")
    parser.add_argument("--from-line", type=int, default=1)
    parser.add_argument("--to-line", type=int)
    args = parser.parse_args()

    source = Path(args.source)
    base_dir = source.parent
    lines = expand(source, base_dir)
    start = max(args.from_line, 1)
    end = args.to_line or len(lines)
    for idx, line in enumerate(lines[start - 1:end], start=start):
        print(f"{idx}: {line}")


if __name__ == "__main__":
    main()
