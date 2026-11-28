---
slug: feature-c-x86-simd-intrinsics-for-pixman
track: C
prio: 65
type: feature
status: backlog
owner: unassigned
created: 2026-11-28
found-by: pxx2 (Panorama all-pxx program; pixx-cc asked for it, as with mbedTLS's AESNI_C)
tags: [cfront, crtl, simd, intrinsics, pixman, panorama, performance]
summary: "pixman's x86 fast paths (pixman-mmx.c, pixman-sse2.c, pixman-ssse3.c) are written with <mmintrin.h>, <xmmintrin.h>, <emmintrin.h> and <tmmintrin.h>, which gcc implements over __builtin_ia32_* and vector types. pxx has neither, so the all-pxx pixman replay builds with -Dmmx=disabled -Dsse2=disabled -Dssse3=disabled, for gcc's reference build too. That is a workaround until this ticket. Panorama renders at 4K through WLR_RENDERER=pixman, so these paths carry the frame time. Wanted: the intrinsic headers pixman uses (pxx's own, written from the Intel intrinsics guide, not copied from gcc or clang), the __m64/__m128i types, and encodings in the backend."
---

# x86 SIMD intrinsics for pixman's fast paths

Status in the replay recipe (/data/tmp/deps-replay.sh, pixman line): SIMD
off until this ticket.

What pixman 0.46.4 uses (to count before starting):
- pixman-mmx.c: `__m64` and `_mm_*` from <mmintrin.h>/<xmmintrin.h>
  (pmulhuw, packuswb, punpck*, pshufw, movntq ...).
- pixman-sse2.c: `__m128i` and <emmintrin.h> (_mm_load_si128,
  _mm_unpacklo_epi8, _mm_mulhi_epu16, _mm_packus_epi16, _mm_adds_epu8, ...).
- pixman-ssse3.c: <tmmintrin.h> (_mm_shuffle_epi8, _mm_alignr_epi8).

Shape of the work:
1. Vector types: `__m64` (8 bytes), `__m128i`/`__m128`/`__m128d` (16
   bytes, 16-aligned), passed and returned in xmm per SysV. The vector
   extensions gcc's headers lean on (`__attribute__((vector_size(16)))`) are
   one way in; a pxx-only intrinsic set lowered straight to instructions is
   the other. Decide that first.
2. Headers in lib/crtl/include, licensed Zlib, written from the Intel
   intrinsics guide.
3. Encodings: asmenc already has much of SSE2 integer (from
   feature-c-inline-asm-sse-and-aes-ni). The codegen needs xmm register
   allocation for these values.
4. Test: pixman's own test suite (scaling, blitters-test, the checksums) with
   SIMD on, compared against gcc, and the Panorama 4K "slow frame" numbers
   before and after.

Related: done/feature-c-inline-asm-sse-and-aes-ni (the inline-asm side),
done/feature-c-builtin-ia32-pause.
