---
title: "C inline asm: SSE registers and AES-NI, so mbedTLS can use its hardware AES"
status: backlog
owner: ""
prio: 45
area: cfront
created: 2026-11-27
found-by: Nodisx curl recipe (pxx2); owner 2026-11-27 "that's worth a ticket"
---

The Nodisx curl recipe builds mbedTLS with MBEDTLS_AESNI_C off, because pxx's
GNU inline asm has no SSE: no `x` (xmm) constraints, no xmm clobbers, and no
assembler encoding for the AES-NI and PCLMULQDQ instructions
(aesenc/aesenclast/aesdec/aesdeclast/aeskeygenassist/aesimc/pclmulqdq,
movdqu/pxor/pshufd...). So TLS runs on mbedTLS's table-based software AES.
That is correct but slower, and it is the variant with the classic
cache-timing side channel (mbedTLS hardens it partly). GCM's GHASH also
loses its PCLMUL path.

mbedTLS 3.x aesni.c has two hardware paths. MBEDTLS_AESNI_HAVE_CODE == 2
uses the intrinsics (<immintrin.h>, _mm_aesenc_si128 & co). == 1 uses GNU
inline asm. Either route closes this ticket:
- intrinsics: crtl <immintrin.h>/<wmmintrin.h> mapping __m128i and the AES
  and CLMUL builtins to pxx codegen; or
- inline asm: `x` constraints and xmm operands in cfront's asm lowering,
  plus the encodings in the in-house x86-64 assembler.
Runtime dispatch (cpuid) is already in mbedTLS.

Done when the curl recipe builds with AESNI on, its test.sh still passes,
and a TLS fetch shows the hardware path (e.g. mbedtls_aesni_has_support()
is true, plus a throughput note against software AES).
