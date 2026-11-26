---
slug: feature-c-inline-asm-sse-and-aes-ni
track: C
prio: 40
type: feature
status: open
owner: pxx2
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
