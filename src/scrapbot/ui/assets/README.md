# Built-in UI font

Scrapbot embeds Inter 4.1 as the always-available default and fallback for UI text. `inter_regular.ttf` is the source font, `inter_mtsdf.bin` is a 512×512 linear RGBA8 MTSDF atlas, and `../font_data.odin` contains the matching ASCII glyph metrics. Project fonts use the separate automatic `build/fonts/` pipeline described by ADR-013.

The generated files use `msdf-atlas-gen` 1.4 with MSDFgen 1.13. Pass the
generator executable to the checked-in regeneration script:

```sh
python3 tools/generate_ui_font.py /path/to/msdf-atlas-gen
```

The script regenerates both `inter_mtsdf.bin` and `../font_data.odin` from
`inter_regular.ttf`.

The font is licensed under the SIL Open Font License 1.1; see `LICENSE.txt`.
