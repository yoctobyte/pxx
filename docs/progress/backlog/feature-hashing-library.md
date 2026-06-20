# Hashing library — CRC32 / MD5 / SHA-256 (known-vector test app)

- **Type:** feature
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-19
- **Closed:** 2026-06-20
- **Relation:** demo-eligible-as-library from idea-demo-app-candidates (new
  catalog entry — strongest pure *oracle*). Sibling to feature-json-library et al.
  Exercises the bit-twiddling lane; pairs with the bit-packing work in
  feature-rtl-conversion-and-bitset-library. Own unit, FPC-ish naming, no port.

## Goal

A `Hashing` unit providing checksum / digest functions over byte buffers and
strings: `CRC32`, `MD5`, `SHA256` (SHA-1 optional). Return raw digest bytes plus
a hex-string helper.

## Surface (sketch)

- `function CRC32(const buf; len): LongWord;`
- `function MD5(const buf; len): TMD5Digest;` / `SHA256(...) : TSHA256Digest;`
- string overloads + `DigestToHex(d): AnsiString`
- streaming context (Init/Update/Final) optional, second slice

## Coverage

UInt32 / Int64 bit ops (rotate / shr / xor / and — rotate especially stresses
codegen) · large static **const tables** (K-constants, CRC table) · byte arrays /
buffer handling · careful width + endianness. **No float, tiny, ESP32-perfect.**

## Acceptance / oracle

- **Published test vectors:** `SHA256("") = e3b0c442...`, `MD5("abc") = 900150983...`,
  known CRC32 values — exact, impossible to fake, no reference renderer needed.
- Byte-identical digests across all targets (real test of 32/64-bit bit codegen).
- Demo: `examples/hashing/` prints digests of a fixed input set vs embedded
  expected values.

## Notes

- These are **integrity/checksum** primitives. Not a password-storage or
  key-derivation recommendation — that is a separate concern if it ever arises.

## Constraints

Own `.pas` unit; FPC-ish naming (cf. FPC `md5` / `sha1` units) but our own impl;
no port; no self-host / cross regression.

## Log
- 2026-06-19 — Opened from the demo/library organization pass.
- 2026-06-20 — Landed `lib/rtl/hashing.pas` with `CRC32*` (streaming + chunk) and `Adler32`. Used by the new `zlib` and `png` units. Wired into `lib-test` / `library-suite-green` via `test/lib_zlib.pas` and `test/lib_png.pas`.
