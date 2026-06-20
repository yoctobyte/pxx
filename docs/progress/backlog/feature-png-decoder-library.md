# PNG decoder library

- **Type:** feature
- **Track:** B
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20
- **Blocked-by:** feature-rtl-image-bitmap-library, feature-compression-library, feature-hashing-library
- **Relation:** Track B image import library. Primary consumer is the adventure
  scene asset pipeline, but the unit should be reusable and demo-independent.

## Goal

A `PNG` unit that decodes PNG files or byte buffers into the shared RTL bitmap
type. Runtime PNG import is useful later, but the immediate adventure path can
use an offline converter so this ticket does not block improving the demo.

## Required pieces

- PNG signature and chunk parser
- IHDR validation
- IDAT concatenation and zlib/deflate inflate
- CRC32 validation
- PNG scanline filters: None, Sub, Up, Average, Paeth
- color types for the first useful slice:
  - truecolor RGB
  - truecolor RGBA
  - grayscale
  - indexed color with PLTE/tRNS, if practical

## Acceptance

- Decode a tiny fixture PNG with known dimensions and pixel values.
- Decode at least one RGB and one RGBA fixture into the shared image type.
- Reject malformed CRC/signature/header fixtures cleanly.
- Provide a library-suite test that is deterministic and does not rely on a GUI.

## Notes

- PNG is not just "read pixels"; deflate and CRC make this a real library stack.
- If full zlib is not ready, start with a host-side/offline converter for demos
  and land runtime PNG decoding when compression/hash foundations are ready.
