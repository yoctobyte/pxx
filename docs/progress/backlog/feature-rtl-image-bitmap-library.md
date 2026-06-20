# RTL image bitmap library

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20
- **Relation:** Track B RTL foundation for PNG import, image conversion, and
  future graphics/image libraries.

## Goal

Provide a small image core unit with an in-memory bitmap type, deliberately not
tied to any file format or renderer. This is the shared data model for decoders
and converters.

Prefer a neutral name such as `Image` or `Bitmap`. `TBitmap` is attractive and
FPC/Lazarus-familiar, but it can imply a GUI toolkit object. A plain RTL
`TImage`/`TBitmap` record with owned pixel storage is enough for the first
slice.

## Surface sketch

- `TRGB` / `TRGBA` pixel records
- `TBitmap` or `TImage` with `Width`, `Height`, and pixel storage
- `CreateBitmap(w, h)`, `FreeBitmap`
- `GetPixel`, `SetPixel`
- helpers for RGB/RGBA conversion and alpha flattening
- optional later: views/slices, resize, palette expansion

## Acceptance

- Library tests create small images, set/get pixels, copy/clear them, and verify
  deterministic pixel values.
- The type is usable by both PNG decode and image-to-ASCII conversion without
  depending on either unit.
- Memory ownership is explicit and works on hosted and constrained targets.

## Notes

- Keep the first version byte-oriented and simple: 8-bit channels, row-major
  layout.
- Avoid GUI concepts such as canvases, handles, fonts, or windows in this unit.

