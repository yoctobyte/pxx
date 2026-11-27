---
slug: feature-c-inline-asm-sse-and-aes-ni
track: C
prio: 40
type: feature
status: done
owner: pxx (c83430; filed by pxx2)
created: 2026-11-26
found-by: pxx2 (Nodisx curl + mbedTLS recipe)
tags: [cfront, inline-asm, x86, crypto]
summary: "pxx's x86 inline-asm encoder has no SSE: mbedTLS's aesni.c (movdqu, pxor, aesenc/aesenclast/aesdec/aesdeclast/aesimc/aeskeygenassist, pclmulqdq, pshufd, and %xmm operands) is refused, so the Nodisx curl recipe builds mbedTLS with MBEDTLS_AESNI_C off and uses its software AES, which is table-based and exposed to cache-timing side channels that AES-NI is not. Encoding that set (plus the xmm clobbers) would let the recipe turn AES-NI back on."
---
# SSE and AES-NI in x86 inline asm

`mbedtls/library/aesni.c` line 506 onwards: `inline asm template has an
unsupported instruction: movdqu`. The instructions mbedTLS's AES-NI path
uses:

movdqu, movdqa, movq, pxor, pshufd, pslldq, psrldq, psllq, psrlq, por, pand,
punpckhqdq, pclmulqdq, aesenc, aesenclast, aesdec, aesdeclast, aesimc,
aeskeygenassist, with %xmm0..%xmm7 operands and `"xmm0"`.. clobbers.

The alternative path in aesni.c is the `<immintrin.h>` intrinsics
(`MBEDTLS_AESNI_HAVE_INTRINSICS`), which pxx does not have either.

Until then `tools/nodisx/curl/record.sh` comments `MBEDTLS_AESNI_C` out of
mbedtls_config.h. The gcc reference uses the same config. When this lands,
drop that edit, re-record, and rerun test.sh: mbedTLS's selftest covers AES.

## Merged 2026-11-27

feature-c-inline-asm-sse-and-aes-ni-for-mbedtls (11-27, owner: "that's worth
a ticket") asked the same thing. Its done-when, met below: the curl recipe
builds with AESNI on, its test.sh passes, and the hardware path is shown in
use with a throughput note against software AES. That ticket is removed.

## Done 2026-11-27 (pxx session)

Which path: aesni.h takes the intrinsics only when `__AES__` and
`__PCLMUL__` are defined (gcc -maes -mpclmul). A plain gcc build, the
recipe's reference, takes the inline-asm path (MBEDTLS_AESNI_HAVE_CODE 1),
so that is the one pxx needed. `punpckhqdq` isn't in mbedTLS 3.6's asm path.

pxx gained:
- asmenc.inc: movdqu/movdqa (F3/66 0F 6F, store 7F), por/pand/pandn; the
  immediate shifts psll/psrl/psra w/d/q and pslldq/psrldq (66 0F 71/72/73
  /ext ib); pshufd (66 0F 70 /r ib). movq with an xmm now has all four
  encodings, each the one gas writes: F3 0F 7E (xmm <- xmm/m64),
  66 0F D6 (m64 <- xmm), and REX.W 66 0F 6E/7E for a GP register. An
  xmm <- xmm movq used to be encoded as the GP form, naming a GP register.
- asmatt.inc: those mnemonics in the AT&T reader; `movq` with an xmm
  operand read as the SSE move, not mov + q; `.byte N,...` inside a
  template (aesenc/aesdec/aesimc/aeskeygenassist/pclmulqdq come as .byte);
  `call Nb`/`Nf`, E8 rel32 like jmp.
- cparser.inc: an "xmmN" clobber no longer marks the GP register of the
  same number busy. Nothing lives in an xmm across a statement, and SysV
  makes every xmm caller-saved.

Tests:
- gas_sse_integer.s: 49 forms, high registers and displacements included.
  pxx's .text is byte-identical to GNU as.
- c_inline_asm_sse_aesni.c: mbedTLS's setkey/ECB/inverse-key templates on
  FIPS-197 C.1 (69c4e0d8...c55a and back), PCLMULQDQ, and the SSE2 rows.
  Its output is gcc's at -O0 and -O2.
- tools/nodisx/curl: record.sh no longer comments MBEDTLS_AESNI_C out.
  test.sh: 46 of 46 rows match the gcc build, and the mbedTLS self-test
  matches. Under pxx the self-test says "AESNI code present (assembly
  implementation)" and "using AESNI", as under gcc.

mbedTLS's programs/test/benchmark.c, built by pxx on plexus (KiB/s, -128):

| | CBC | CTR | GCM |
|---|---|---|---|
| pxx, AES-NI | 27045 | 22917 | 8903 |
| pxx, software AES | 6145 | 6318 | 764 |
| gcc -O2, AES-NI | 241595 | 250886 | 69797 |

Run to run the pxx numbers vary by about 20%. AES-NI is 4x (CBC/CTR) to
12x (GCM, PCLMUL GHASH) software AES under pxx. The remaining 9x to gcc is
pxx's code around the asm blocks, which are the same bytes:
feature-c-toybox-size-gap-literal-headers-call-realign-no-regalloc (3).

Not done: the intrinsics path (<immintrin.h>/<wmmintrin.h>), which nothing
needs while gcc's reference takes the asm path; and i386, whose text sink
refuses these mnemonics by name (no i386 user).
