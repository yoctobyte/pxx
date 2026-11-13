---
track: C
tags: [c, attributes, int128, miscompile, dropbear, libtommath]
prio: 80
type: bug
blocked-by: []
summary: "`__attribute__((mode(TI)))` was skipped like any other attribute, so a typedef asking for a 128-bit integer silently became 64 bits wide. libtommath picks exactly that for its mp_word on any __GNUC__ x86-64 compiler, and pxx defines __GNUC__, so every digit product lost its high half. dropbear's RSA key generation never terminated and ECDSA failed. mode(TI) and the other >64-bit modes are now refused by name."
status: done
owner: claude
---

# `mode(TI)` was ignored and made a 64-bit type

Found running the pxx-built dropbear 2026.94
([[feature-c-dropbear-builds-with-pxx]]). `dropbearkey -t rsa` ran for
30 minutes; gcc's build takes about a second. `-t ecdsa` printed `ECC error`.

**Cause.** `libtommath/tommath.h`:

```c
#if defined(__x86_64__) ...
#   if defined(__GNUC__) && !defined(__hppa)
#      define MP_64BIT
...
typedef uint64_t mp_digit;
typedef unsigned long private_mp_word __attribute__((mode(TI)));
```

pxx defines `__GNUC__`, and the C lexer skipped `__attribute__((...))`
except for `packed` and `aligned`. The 128-bit `mp_word` was therefore a
plain 64-bit `unsigned long`, and every `(mp_word)a * b` dropped its top
64 bits. A differential harness over 26 libtommath operations matched gcc on
add and sub only. Every multiply, divide and modular operation differed, and
Miller-Rabin called the P-256 prime composite.

The ticket had predicted that libtommath would fall back to `MP_32BIT` by
itself when pxx lacks `__int128`. It does not: libtommath never tests for
`__SIZEOF_INT128__`, only for `__GNUC__`.

**Fix.** `compiler/clexer.inc` reads the mode named in an attribute
(`CAttrModeName`, accepting both `mode(TI)` and `__mode__(__TI__)`).
TI, OI, TF, XF and KF are refused with an error that names the attribute
and the libtommath workaround. The narrower modes (QI, HI, SI, DI, word) are
still skipped; the real feature is [[feature-c-int128-and-attribute-mode]].

**dropbear.** `tools/dropbear_pxx.py` now builds both the gcc reference and
the pxx build with `CFLAGS=-Os -W -Wall -DMP_32BIT`. That is libtommath's own
32-bit-digit configuration, set through configure, with no source changed.
Under it, the harness's 28 output lines are identical for gcc and pxx.

**Test.** `test/c_attribute_mode_ti_is_refused.c`, two rows:

- **Positive control:** QI, `__mode__(__word__)` and an identifier
  containing `mode` still compile.
- **Refusal:** with `-dMODE_TI_ROW`, the `mode(TI)` typedef is refused and
  the error names it.
