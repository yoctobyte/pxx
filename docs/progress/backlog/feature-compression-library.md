# Compression library — Huffman / LZ77 (roundtrip test app)

- **Type:** feature
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-19
- **Closed:** 2026-06-20
- **Relation:** demo-eligible-as-library from idea-demo-app-candidates. Sibling
  to feature-json-library et al. **Depends on** the bit-stream / bit-set work in
  feature-rtl-conversion-and-bitset-library (encode/decode is bit-granular).
  Own unit, FPC-ish naming, no port.

## Goal

A `Compression` unit: lossless encode/decode of byte buffers. Start with
**Huffman** (canonical), optionally add **LZ77** then a deflate-lite combining
both. Decompress(Compress(x)) = x.

## Surface (sketch)

- `function HuffmanCompress(const src): TBytes;`
- `function HuffmanDecompress(const src): TBytes;`
- later: `LZ77Compress` / `Deflate` variants
- a bit-reader / bit-writer over packed words (from the bit-set lane)

## Coverage

**bit packing / bit streams** (the motivating consumer of the bit-set type) ·
trees (Huffman tree build/walk) · frequency tables = collections/hashing ·
dynamic arrays · recursion (tree). Integer-deterministic throughout.

## Acceptance / oracle

- **Roundtrip identity:** `Decompress(Compress(buf)) = buf` for a fixed corpus.
- **Exact compressed size** (integer) per input — byte-identical across targets.
- Demo: `examples/compression/` compresses a bundled corpus, prints sizes +
  verifies roundtrip.

## Constraints

Own `.pas` unit; FPC-ish naming; no port; blocked-ish on the bit-set primitive
landing first (can prototype a local bit-writer, but the real unit should consume
the shared type). No self-host / cross regression.

## Log
- 2026-06-19 — Opened from the demo/library organization pass.
- 2026-06-20 — Landed `lib/rtl/zlib.pas`: RFC 1950/1951 inflate (stored, fixed Huffman, dynamic Huffman) with Adler-32 validation, plus `DeflateZlibStored` for encoding. Added `test/lib_zlib.pas` covering roundtrip, fixed/dynamic fixtures, and malformed-stream rejection. Green in `lib-test` and `library-suite-green`.
