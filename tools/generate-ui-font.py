#!/usr/bin/env python3
"""Generate Machina's built-in UI bitmap font table from a BDF font."""

from __future__ import annotations

import argparse
from pathlib import Path


FIRST_CODEPOINT = 32
LAST_CODEPOINT = 126
FALLBACK_CODEPOINT = 63


def row_type_for_width(width: int) -> tuple[str, str]:
    if width <= 8:
        return "u8", "u3"
    if width <= 16:
        return "u16", "u4"
    if width <= 32:
        return "u32", "u5"
    if width <= 64:
        return "u64", "u6"
    raise ValueError(f"unsupported BDF glyph width {width}")


def parse_bdf(path: Path) -> tuple[dict[int, list[int]], int, int, int, str]:
    glyphs: dict[int, list[int]] = {}
    names: dict[int, str] = {}
    width: int | None = None
    height: int | None = None
    advance: int | None = None
    version = "unknown"
    current_codepoint: int | None = None
    current_name: str | None = None
    current_rows: list[int] | None = None

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line.startswith("COMMENT  * Spleen "):
            parts = line.split()
            if len(parts) >= 5 and parts[2] == "Spleen" and "x" in parts[3]:
                version = parts[4]
        elif line.startswith("FONTBOUNDINGBOX "):
            parts = line.split()
            width = int(parts[1])
            height = int(parts[2])
        elif line.startswith("STARTCHAR "):
            current_name = line.removeprefix("STARTCHAR ")
            current_codepoint = None
            current_rows = None
        elif line.startswith("ENCODING "):
            current_codepoint = int(line.split()[1])
        elif line.startswith("DWIDTH ") and current_codepoint is not None and advance is None:
            advance = int(line.split()[1])
        elif line == "BITMAP":
            current_rows = []
        elif line == "ENDCHAR":
            if current_codepoint is not None and current_rows is not None:
                glyphs[current_codepoint] = current_rows
                names[current_codepoint] = current_name or f"U+{current_codepoint:04X}"
            current_codepoint = None
            current_name = None
            current_rows = None
        elif current_rows is not None:
            current_rows.append(int(line, 16))

    if width is None or height is None or advance is None:
        raise ValueError("BDF is missing FONTBOUNDINGBOX or DWIDTH metadata")

    for codepoint in range(FIRST_CODEPOINT, LAST_CODEPOINT + 1):
        rows = glyphs.get(codepoint)
        if rows is None:
            raise ValueError(f"BDF is missing ASCII codepoint {codepoint}")
        if len(rows) != height:
            raise ValueError(f"codepoint {codepoint} has {len(rows)} rows, expected {height}")

    return glyphs, width, height, advance, version


def comment_for_codepoint(codepoint: int) -> str:
    char = chr(codepoint)
    if codepoint == 32:
        return "SPACE"
    if char == "\\":
        return "U+005C"
    if char.isprintable():
        return char
    return f"U+{codepoint:04X}"


def generate(input_path: Path, output_path: Path) -> None:
    glyphs, width, height, advance, version = parse_bdf(input_path)
    row_type, bit_shift_type = row_type_for_width(width)
    hex_digits = (width + 3) // 4

    lines: list[str] = []
    lines.append(f"//! Generated from Spleen {width}x{height} {version} (BSD-2-Clause).")
    lines.append(f"//! Source: {input_path.as_posix()}")
    lines.append("//! Upstream: https://github.com/fcambus/spleen")
    lines.append(
        f"//! Regenerate with: python3 tools/generate-ui-font.py {input_path.as_posix()} {output_path.as_posix()}"
    )
    lines.append("//! See third_party/spleen/LICENSE for copyright and license terms.")
    lines.append("")
    lines.append(f"pub const Row = {row_type};")
    lines.append(f"pub const BitShift = {bit_shift_type};")
    lines.append(f"pub const width: usize = {width};")
    lines.append(f"pub const height: usize = {height};")
    lines.append(f"pub const advance: usize = {advance};")
    lines.append(f"pub const first_codepoint: u8 = {FIRST_CODEPOINT};")
    lines.append(f"pub const fallback_codepoint: u8 = {FALLBACK_CODEPOINT};")
    lines.append("")
    lines.append("pub fn glyphRows(byte: u8) [height]Row {")
    lines.append(f"    if (byte < first_codepoint or byte > {LAST_CODEPOINT}) {{")
    lines.append("        return glyphs[fallback_codepoint - first_codepoint];")
    lines.append("    }")
    lines.append("    return glyphs[byte - first_codepoint];")
    lines.append("}")
    lines.append("")
    lines.append("const glyphs = [_][height]Row{")

    for codepoint in range(FIRST_CODEPOINT, LAST_CODEPOINT + 1):
        rows = glyphs[codepoint]
        lines.append(f"    // {codepoint}: {comment_for_codepoint(codepoint)}")
        formatted_rows = ", ".join(f"0x{row:0{hex_digits}x}" for row in rows)
        lines.append(f"    .{{ {formatted_rows} }},")

    lines.append("};")
    lines.append("")

    output_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    generate(args.input, args.output)


if __name__ == "__main__":
    main()
