#!/usr/bin/env python3
"""Focused deterministic tests for the SVG icon compiler."""

from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPILER = ROOT / "bin" / "scrapbot-iconc"


def run(source: Path, output: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            str(COMPILER),
            str(source),
            "--font-out",
            str(output / "icons.ttf"),
            "--map-out",
            str(output / "icons.json"),
            "--charset-out",
            str(output / "icons.charset"),
        ],
        check=False,
        capture_output=True,
        text=True,
    )


def main() -> int:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        source = root / "source"
        source.mkdir()
        (source / "play.svg").write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
            '<path fill="currentColor" d="M5 3L19 12L5 21Z"/></svg>',
            encoding="utf-8",
        )
        (source / "search.svg").write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
            'fill="none" stroke="black" stroke-width="2">'
            '<circle cx="11" cy="11" r="7"/><path d="m16 16 5 5"/></svg>',
            encoding="utf-8",
        )
        first = root / "first"
        second = root / "second"
        first.mkdir()
        second.mkdir()
        first_result = run(source, first)
        second_result = run(source, second)
        assert first_result.returncode == 0, first_result.stderr
        assert second_result.returncode == 0, second_result.stderr
        for name in ("icons.ttf", "icons.json", "icons.charset"):
            assert (first / name).read_bytes() == (second / name).read_bytes(), name
        metadata = json.loads((first / "icons.json").read_text(encoding="utf-8"))
        assert [item["name"] for item in metadata["symbols"]] == ["play", "search"]
        assert [item["codepoint"] for item in metadata["symbols"]] == [
            0xE000,
            0xE001,
        ]

        (source / "bad.svg").write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
            '<linearGradient id="gradient"/><path fill="url(#gradient)" '
            'd="M0 0H24V24H0Z"/></svg>',
            encoding="utf-8",
        )
        rejected = root / "rejected"
        rejected.mkdir()
        rejected_result = run(source, rejected)
        assert rejected_result.returncode != 0
        assert "unsupported SVG feature" in rejected_result.stderr
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
