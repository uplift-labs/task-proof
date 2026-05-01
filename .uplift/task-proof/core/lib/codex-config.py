#!/usr/bin/env python3
"""Small Codex config patcher for task-proof installs.

Currently only ensures:

    [features]
    codex_hooks = true

The file is deliberately line-oriented instead of a full TOML rewriter so it
does not reorder or normalize user-owned config.
"""
import re
import sys
from pathlib import Path


def ensure_codex_hooks(text: str) -> str:
    lines = text.splitlines()
    had_trailing_newline = text.endswith("\n")

    features_start = None
    features_end = len(lines)
    key_index = None

    current_section = None
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            current_section = stripped
            if stripped == "[features]":
                features_start = i
                features_end = len(lines)
                continue
            if features_start is not None and features_end == len(lines):
                features_end = i
                current_section = stripped
                continue

        if current_section == "[features]" and re.match(r"\s*codex_hooks\s*=", line):
            key_index = i

    if features_start is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend(["[features]", "codex_hooks = true"])
    elif key_index is not None:
        indent = re.match(r"^(\s*)", lines[key_index]).group(1)
        lines[key_index] = f"{indent}codex_hooks = true"
    else:
        lines.insert(features_end, "codex_hooks = true")

    result = "\n".join(lines)
    if result or had_trailing_newline:
        result += "\n"
    return result


def main() -> None:
    if len(sys.argv) != 3 or sys.argv[2] != "--enable-hooks":
        print(f"Usage: {sys.argv[0]} <config.toml> --enable-hooks", file=sys.stderr)
        sys.exit(1)

    path = Path(sys.argv[1])
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    result = ensure_codex_hooks(text)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(result, encoding="utf-8")


if __name__ == "__main__":
    main()
