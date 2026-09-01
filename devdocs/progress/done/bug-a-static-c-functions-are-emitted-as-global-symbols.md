---
slug: bug-a-static-c-functions-are-emitted-as-global-symbols
title: "`static` on a C function was ignored by the object writer, so every TU exported its private helpers"
track: A
prio: 65
type: bug
status: done
created: 2026-09-01
found-by: frankD
owner: frankD
blocked-by: []
summary: "FIXED 2026-09-01. C 6.2.2p3 gives a `static` function internal linkage; --emit-obj emitted every C-convention proc as STB_GLOBAL, so any two objects that included a header defining `static` helpers collided. Found by attempting the 82-object busybox userland, which died on `multiple definition of bb_ascii_isalnum / bb_strtoi32 / is_tty_secure / new_tls_state`. The data side already read SymCStaticLink; functions were the arm that never got the sibling. New ProcCStaticLink, set at the definition, read by ObjProcIsExported -- no new symbol group, since a defined-but-unexported proc already lands in the LOCAL block."
---

# `static` stopped at the data side

`ObjDataIsLocal` has read `SymCStaticLink` since the object-linkage work
landed. `ObjProcIsExported` was `Result := ProcCdecl[procIdx]` and asked
nothing about linkage, so **`static int helper(int)` came out `T` where gcc
emits `t`** — measured on a two-file repro before anything else.

That is the double-case rule failing in the ordinary way: one arm was fixed,
the sibling was never grepped for.

## How it was found

By attempting the target, not by reading the backlog. The 26-applet busybox
userland compiled to 82 objects and the link died:

```
multiple definition of `bb_ascii_isalnum'
multiple definition of `bb_ascii_isxdigit'
multiple definition of `bb_ascii_tolower'
multiple definition of `bb_ascii_toupper'
multiple definition of `bb_strtoi32'
multiple definition of `bb_strtol'
multiple definition of `bb_strtou32'
multiple definition of `bb_strtoul'
multiple definition of `is_tty_secure'
multiple definition of `new_tls_state'
```

Every one is `static ALWAYS_INLINE` in `include/libbb.h` or
`include/xatonum.h`, and every translation unit includes them.

**The harness could not say that until it was fixed too.** Its link-failure
report grepped only for `undefined reference`, so a link that died on multiple
definitions printed the FAIL line and no cause at all. A diagnostic silent on
half its population is the half you spend the hour on.

## The fix

`ProcCStaticLink`, the proc-side twin of `SymCStaticLink`:

- read in `ParseCSubroutine` beside `hdrStaticBody`, **before `ParseCDeclType`
  moves `TokPos` past the type token** `CDeclSawStatic` scans backwards from;
- recorded at the definition, beside the module attribution, and only ever SET
  — C 6.2.2p5 makes a later specifier-less declaration inherit the earlier
  `static`, so a plain redeclaration must not turn the symbol global again;
- read by `ObjProcIsExported`.

`hdrStaticBody` could not stand in for it: that asks the narrower question of a
bodied static reached through a *header import*, and is False for the ordinary
case of a static defined in the `.c` the user named.

No new symbol group was needed. A defined-but-unexported proc already lands in
the LOCAL block ahead of `firstGlobal` — where every non-`cdecl` Pascal routine
has always gone.

## Why LOCAL and not WEAK

Weak also links, and is wrong. The linker would keep ONE body and both
translation units would call it; internal linkage means each has its own.
`test/c_obj_static_link_{a,b}.c` define the same two `static` names with
DIFFERENT bodies for exactly this reason, so the OUTPUT discriminates: `a 11 /
b 2200` under internal linkage, both rows collapsing onto one body under a weak
fix. gcc building the same two sources is the oracle, and the symbol-binding
assertion is aimed both ways — `a_probe` must still come out GLOBAL, or a
writer that localised everything would pass.

## Verified

- Two-object repro: `t` for the static, `T` for the non-static, links, and
  prints what gcc prints.
- `tools/gate.sh quick` GREEN with the FPC seed canary concurrent.
- `tools/busybox_diff.sh --separate` **GREEN**: 82 objects, a real link with no
  `-Wl,-z,muldefs`, byte-identical to the gcc oracle over 154 cases.
