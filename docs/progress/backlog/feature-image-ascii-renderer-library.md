# Image to ANSI ASCII renderer library

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20
- **Blocked-by:** feature-rtl-image-bitmap-library, feature-terminal-ansi-library
- **Relation:** Track B renderer library. Lets console demos display rich scene
  art without embedding renderer logic in each app.

## Goal

Convert a bitmap into terminal-friendly art. The primary target is ANSI
truecolor half-block rendering, with plain ASCII as a portable fallback.

## Render modes

- Plain luminance ASCII using a ramp such as ` .:-=+*#%@`.
- ANSI colored ASCII using foreground color per cell.
- ANSI truecolor half-block mode:
  - glyph `▀`
  - foreground color = upper source pixel
  - background color = lower source pixel
  - one terminal cell represents two vertical pixels

## Surface sketch

- `RenderAscii(const img: TBitmap; width, height: Integer): AnsiString`
- `RenderAnsi256(...)`
- `RenderAnsiTrueColorHalfBlock(...)`
- optional: dithering, aspect correction, palette reduction, gamma correction

## Acceptance

- Tiny bitmap fixtures render to exact expected byte strings.
- Half-block rendering handles odd image heights deterministically.
- The unit depends on the image core and terminal ANSI helpers, not on PNG.
- `examples/adventure` can load or embed pre-rendered `.ansi` scenes generated
  by this library or an equivalent host tool.

## Notes

- Runtime rendering and offline asset generation should share the same algorithm
  eventually.
- Keep the first slice deterministic; art quality tweaks can come later.

