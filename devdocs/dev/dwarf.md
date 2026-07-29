# Debugging pxx programs with gdb

```sh
compiler/pascal26 -g prog.py out          # or prog.pas
gdb ./out
(gdb) source tools/pxx-gdb.py             # Variant decoding + `pxxrc`
(gdb) break combine
(gdb) run
```

`-g` only forces `-O0` when no `-O` is given, so **`-g -O2` works** and is
usually what you want: it is the optimisation level the ownership bugs actually
appear at. Verified — breakpoints, correct lines, args, locals and stepping all
work at `-O2`.

## What works

Pascal, **NilPy**, **C**, **Rust** and **Zig** (only Pascal had any debug info
before 2026-07-29 — every other frontend answered "Function not defined" to
`break`):

| | |
| --- | --- |
| `break <func>` / `break file.py:LINE` | yes, for defs, methods, lambdas |
| backtrace with source lines | yes, including the module body (`main`) |
| `info args` / `info locals` | yes |
| `next` / `step` / `finish` | yes |
| expression evaluation (`print a+b`) | yes |
| fields through an object (`print n.name`) | yes |
| strings | print their text, not the handle |
| Variants | `{VType=6, Payload=...}`, or decoded with the printer |

Pascal syntax notes: dereference is `p^`, not `*p`; `ptype x` shows the record
layout.

## The pretty-printer — `tools/pxx-gdb.py`

```
(gdb) print got
$1 = 'value' (str)
(gdb) print num
$2 = 7
(gdb) pxxrc n
0x7fffd7e00018: obj, refcount 1
```

Without it a Variant prints as `{VType = 6, Payload = 140736815169664}`, and
before the DWARF work it printed as `0x6` — the tag misread as a pointer, which
*looks like an address* and is worse than no answer at all.

`pxxrc EXPR` is the one that matters: **the refcount lives at `[inst-16]`,
below the pointer the debugger shows you**, so it was previously invisible.
Half the bugs in this runtime are "who took a reference and who dropped it".
`pxxrc` accepts an object pointer or a Variant (it reports the payload).

Under `-dPXX_HEAP_DEBUG` a quarantined block is named as freed rather than
printed as whatever its recycled bytes look like. (That branch is reviewed but
not yet exercised by a test — NilPy class slots are never released, so an
object is hard to kill on purpose. Marked here rather than claimed as verified.)

## Recommended combination for an ownership bug

1. `-g -O2 -dPXX_HEAP_DEBUG` — poison tells you *that* there is a
   use-after-free and which read hits it (see `devdocs/dev/debug-heap.md`).
2. `pxxrc` at the suspect points — who is holding a reference, and how many.
3. `-dPXX_OBJTRACE` if it is still not obvious — the full retain/release log
   for one address.

## Limits

- **One file per CU.** The line table describes the main source file only;
  imported `.py` modules and Pascal units lex past `DbgMainTokEnd` and get line
  0, so you cannot break on a line inside an imported module. This is the
  Tier 1 design, not an oversight — but it is the biggest remaining gap for a
  multi-module app like songformatter.
- **C line numbers index the PREPROCESSED text.** Breakpoints, args, locals
  and stepping are correct, but `break addup` reports `dbgc.c:2068` for an
  18-line file — `CPreprocess` inlines every `#include` and the lexer numbers
  lines in that buffer. Needs an origin map in `cpreproc.inc` (which keeps no
  line information at all today) AND multi-file CU support, since headers are
  legitimately other files. See
  `bug-c-dwarf-lines-index-the-preprocessed-text`. Rust and Zig have no
  preprocessor and are correct.
- `TPyList` / `TPyDict` have no pretty-printer yet, so a list prints as an
  object pointer. `pxxrc` at least gives its refcount.
- Managed AnsiString refcounts are not traced by `-dPXX_OBJTRACE` (it covers
  `PXXObj*` only).
- No DWARF for the cross targets' own debuggers; this is x86-64 hosted gdb.

## Related

- `devdocs/dev/debug-heap.md` — the `-dPXX_HEAP_DEBUG` / `-dPXX_OBJTRACE`
  switches.
- `devdocs/progress/backlog/feature-debuggability-umbrella.md`.
