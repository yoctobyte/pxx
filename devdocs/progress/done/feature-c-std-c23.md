---
slug: feature-c-std-c23
track: C
prio: 70
type: feature
status: done
owner: pxx2
created: 2026-11-27
closed: 2026-11-27
found-by: pxx2 (wlroots 0.20.2 replay for Panorama: every unit is -std=c23)
tags: [cfront, c23, wlroots, panorama]
related: [feature-tools-a-generic-compdb-replay, feature-crtl-wlroots-gaps]
summary: "-std=c23 / gnu23 (and c2x, gnu2x, iso9899:2024) accepted, as far as real code needs and no further: __STDC_VERSION__ 202311L; bool, true, false (type bool: sizeof 1, _Generic _Bool), alignas, alignof, thread_local as keywords (static_assert, typeof were); true/false in #if and in constant expressions; [[...]] attributes, the ones that change no code dropped, the rest refused by name; __has_c_attribute; a <stdbool.h> that defines only its marker; __VA_OPT__ in every mode, as gcc. wlroots: 0/228 to 228/228 as built. Not implemented, and an error where used: nullptr, constexpr, auto inference, _BitInt, #embed, #elifdef/#elifndef, u8 character constants. Tests c_c23_26, c_gnu23_26, c_vaopt26, c_vaopt23_26, c_c23ref26."
---

# -std=c23

pxx refused `-std=c23` rather than compile C17 under it, and every one of
wlroots' units asks for it (meson's `c_std=c23`). With -std=gnu17 swapped in
as a measurement, all 228 compiled (after feature-crtl-wlroots-gaps), so
what wlroots needs of C23 is small; this is that, done properly, plus what a
C23 mode cannot honestly lack.

## What the mode does

- `__STDC_VERSION__` is 202311L; the `c` spellings set `__STRICT_ANSI__`.
  The last `-std=` wins (it reset neither flag before).
- **Keywords.** `bool`, `alignof` and `thread_local` are renamed in the lexer,
  after preprocessing, to `_Bool`, `_Alignof` and `_Thread_local`, so
  `#ifdef bool` stays false as in C23; `alignas` is read where `_Alignas` is
  (CSkipSpace). `static_assert` (message optional) and `typeof` were read already.
- **`true`/`false`** are constants of type bool (`sizeof(true)` is 1,
  `_Generic` picks `_Bool`): ParseCPrimary makes them `tyBool8` literals,
  CEvalConstPrimary 1 and 0 (wlroots' file-scope `static bool colored =
  true`), and `#if true` is 1 (6.10.1p11). Being keywords they name nothing
  else, so matching the word is exact.
- **`[[attributes]]`** (6.7.13) are read at token boundaries. The standard ones
  and the gnu:: ones that only steer warnings or the optimiser are dropped.
  Any other (`gnu::packed`, `aligned`, `section`, `cleanup`, `visibility`, ...)
  changes layout, linkage or behaviour, and is refused by name, pointing at
  the `__attribute__` spelling, rather than ignored. A `]]` inside a string
  argument is text.
- **`__has_c_attribute`** answers 202311 (gcc 15's value) for the standard
  attributes, 1 for the gnu:: ones the lexer drops, 0 for the rest and for
  everything outside C23 mode, where `[[` is not read: a yes for an attribute
  the lexer then refused would turn a probe into an error. `#ifdef
  __has_c_attribute` is true, as `__has_include`'s is.
- **`<stdbool.h>`** defines only `__bool_true_false_are_defined` under C23:
  its `#define true 1` would make true an int again.
- **`__VA_OPT__`** (6.10.5.1), in every C mode as gcc reads it: the content,
  parameters substituted, when the variadic arguments hold a token; nothing
  when they are omitted, empty or blank. 94 of wlroots' units use it
  (wlr_log: `fmt, __FILE__, __LINE__ __VA_OPT__(,) __VA_ARGS__`). An absent
  group leaves a space only where its neighbours could glue.

## Not implemented

Each is an error where it is used, never silently another meaning:
`nullptr`/`nullptr_t`, `constexpr`, `auto` type inference, `_BitInt`,
`#embed`, `#elifdef`/`#elifndef`, `u8` character constants (char8_t), digit separators. The census will say
which come next.

## Checks

`c_c23_26` / `c_gnu23_26` (test/c_std_c23.c) against gcc 15 `-std=c23` and
`-std=gnu23`: `#if true`, `#ifdef bool`/`true`, sizeof and _Generic of true,
bool conversion, `alignas` member offsets and `alignof`, static_assert with and
without message, attributes on functions, members, locals and statements
(fallthrough), a deprecated message holding `]]`, gnu:: attributes,
thread_local, `__has_c_attribute`. `c_vaopt26` / `c_vaopt23_26`
(test/c_va_opt.c): omitted, empty and blank variadic arguments, a named
parameter inside the content, adjacent brackets, the wlr_log shape run.
`c_c23ref26`: `[[gnu::packed]]` refused by name, `nullptr` an error, `-std=c89`
refused, gnu17's `true` still an int.

wlroots (PXXFLAGS=--threadsafe: libxcb's headers bring <pthread.h>): 0/228
compiled as built before, 228/228 after.
