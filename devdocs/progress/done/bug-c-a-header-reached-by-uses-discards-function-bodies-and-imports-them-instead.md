---
slug: bug-c-a-header-reached-by-uses-discards-function-bodies-and-imports-them-instead
track: C
type: bug
prio: 55
status: done
found: 2026-08-29
found-by: pxx-a5
summary: "A `static`/`static inline` function DEFINED in a .h reached through `uses` has its body discarded and becomes an external, so the program links a DT_NEEDED on a lib<header>.so that does not exist and dies at load. The identical function in a .c compiles and runs. Discovered while fixing bug-a-a-c-include-path-captures-a-pascal-uses; it is the OTHER half of that ticket's silent arm and survives its fix."
owner: frankC
---

# `uses <header>` throws away the header's function bodies, then imports them

## Measured, at `62714dc5eb06`

Same function, two files. Only the extension differs:

| the file | result |
| --- | --- |
| `zzhdr3.h` — `static int zzstat(void) { return 4242; }` | `ok:`, then **`error while loading shared libraries: libzzhdr3.so`** |
| `zzc.c` — the same function | `ok:`, runs, prints `4242` |

```
$ pascal26 -Ip4 a4.pas /tmp/a4      # a4.pas: uses zzhdr3; writeln(zzstat())
ok: /tmp/a4  [ ... ]
$ readelf -d /tmp/a4 | grep NEEDED
 0x0000000000000001 (NEEDED)   Shared library: [libzzhdr3.so]
$ /tmp/a4
/tmp/a4: error while loading shared libraries: libzzhdr3.so: ...
```

`static inline` — the shape that is in every real C header — behaves the same:
`libzzinl_h.so`, same load failure.

## The invariant, asserted in a comment, and false

`cparser.inc:12898`:

> *A HEADER declares and defines nothing, so its single registration pass is
> already the whole job*

and `cparser.inc:10510`:

> *In true header-import mode bodies stay external.*

That reading is right for an FFI surface — `sqlite3.h` declares, `libsqlite3.so`
defines — and it is what the whole `uses <header>` mechanism is built on. It is
simply not true of C headers in general: `static` and `static inline`
definitions are ordinary, and for those there is no library to import from,
because the definition *is* in the header.

So the header path takes a function it was handed the body of, drops the body,
marks it external, and synthesises a soname from the header's own stem
(`ConcatThree('lib', LowerCase(cName), '.so', ...)`, `pasparser_proc.inc`).
Nothing in that chain can fail, which is why it is silent.

## Why this is filed separately from the ticket that found it

[[bug-a-a-c-include-path-captures-a-pascal-uses-and-emits-a-dynamic-import]] is
about a C header *winning a name it should not have won*. Its probe

```c
static int pxx_probe_marker(void) { return 4242; }
```

produced the unloadable binary, and that made the DT_NEEDED look like part of
the same defect. It is not. Fixing the resolver removes the collision for
`math` / `netdb` / `strings` / `png` — those `uses` now bind their `.pas` — but
**a header with a non-colliding name still does this**, and the two examples
above are from the compiler with that fix in.

One is unit resolution (Track A, done). This one is what the C header path does
once it legitimately owns the name, and it is Track C's.

## What the fix has to decide

Not obvious, which is why this is a ticket and not a patch:

1. **Compile the body**, the way the `.c` path does. Most useful, matches what
   the programmer wrote, and is what `static inline` means. Risk: a header
   included by several translation units now defines the symbol in each.
2. **Refuse it** — a bodied function in a header-import surface is an error,
   naming the function. Cheap and honest, and would have surfaced this the day
   it was written; but it breaks any header that has a `static inline` beside
   the declarations you actually want, which is most system headers.
3. **Keep the extern, drop the invented soname.** Narrowest: it does not fix
   the wrong answer, only stops it becoming an unloadable binary. A link error
   beats a load error, but 1 is what the user meant.

Option 1 for a `static`/`static inline` definition and the current behaviour
for a bare declaration is probably the whole answer, since the C standard
already separates those two cases for exactly this reason.

## Gate

Track C's: C tests green + self-host byte-identical + cross. Plus the pair
above — the same `static` function in a `.h` and a `.c` must agree — and no
binary may acquire a `DT_NEEDED` on a `lib<header-stem>.so` that the header
itself defines.

## RESOLVED — 2026-08-30 (frankC)

**Option 1, scoped to `static`/`static inline` exactly as the ticket
recommended**, and the recommendation held up under measurement rather than
merely sounding right. A bodied `static` in a header-import surface now falls
through to ordinary compilation; everything else keeps its old treatment.

### The measurement that made option 1 safe, and it was not obvious

The ticket's option 2 was rejected on the grounds that refusing a bodied
function "breaks any header that has a `static inline` beside the declarations
you actually want, which is most system headers". The same worry applies to
option 1 from the other side: if bodies are compiled eagerly, every uncalled
`static inline` in every `uses`d system header gets compiled, and those are
exactly the ones full of builtins and asm.

**So I measured what an UNCALLED bodied static does today: nothing.** No
`DT_NEEDED`, binary runs, exit 0. The damage requires a *call*. That bounds the
change: headers whose statics are never called are unaffected either way, and
the ones that are called are today producing unloadable binaries. Neither
option's stated risk survives contact with that fact, and it is why this is a
one-branch change rather than a redesign of the header walk.

### What changed

`ParseCSubroutine`, `compiler/cparser.inc`, three edits and one new helper —
**no shared-internals file touched, so no Track A ticket was needed.**

- `CDeclSawStatic(typeIdx)` scans **backward** over the storage-class and
  function specifiers that `CIsTopLevelSkipIdent` lets the top-level walks skip
  without recording. Backward rather than a flag threaded through the callers
  because those specifiers are skipped in **three** separate loops (program
  pass 1, the crtl pull, the header walk) and a flag would have to be set and
  cleared correctly in all three; the token stream already holds the answer.
- It is deliberately conservative — an intervening `__attribute__((...))` makes
  it answer False, which leaves the caller on the pre-existing behaviour. **A
  missed `static` is a bug that stays; a hallucinated one would compile a body
  that should have been imported.** The asymmetry picks the direction.
- `if CHeaderMode then` becomes `if CHeaderMode and not hdrStaticBody then`,
  where `hdrStaticBody` is computed at entry, before any `Next` moves `TokPos`
  past the type token.

The invariant in the comment at the header walk — *"A HEADER declares and
defines nothing"* — is now false only for the case it was already false for,
and the code no longer acts on it there.

### Evidence

| case | before | after |
| --- | --- | --- |
| `static` in a `.h`, called | `DT_NEEDED libhdrstatic.so`, **dies at load** | prints `4242` |
| `static inline` in a `.h`, called | same, dies at load | prints `42` |
| bodied `static` in a `.h`, **not** called | harmless (no import) | harmless |
| the same `static` in a `.c` | prints `4242` | prints `4242` |
| bare declaration in a `.h` | imports `lib<stem>.so` | **unchanged** |

The last row is the one worth being explicit about: `uses sqlite3` binding to
`libsqlite3.so` is the whole point of the header path, and it had to survive.
Verified by building the pre-fix and post-fix compilers and compiling the same
program with both — identical `DT_NEEDED` either way.

- `test/test_header_static_body.pas` + `test/test_header_static_body_c.pas`
  over `test/chdrstatic/`: **the pair is the invariant** — the same source text
  must behave the same whichever extension it is given. Both print `4242 / 42`.
  The pre-fix compiler passes the `.c` half and fails the `.h` half, so the
  test was shown capable of failing before its green was used.
- The recipe also asserts no `DT_NEEDED` on `libhdrstatic.so`. It was first
  written `grep -qv`, which passes whenever *any* line fails to match — i.e.
  every ELF, i.e. never fails. Caught and rewritten as a negated `grep -q`,
  then **validated in both directions**: it passes on the fixed binary and
  fails on the pre-fix one.
- Differential over 37 named C tests: **all 37 byte-identical.** The header
  path is only reachable through `uses <header>`, so no `#include`-driven C
  program is affected, which the differential confirms rather than assumes.
- Self-host fixedpoint `5807b27f78dc`; `tools/gate.sh quick` **GREEN**.

### What is deliberately NOT fixed

A **non-static** bodied function in a header keeps the old extern-plus-invented-
soname treatment. It is still wrong by the same argument, but the ticket
measured `static`, `static` is what the C standard separates out for exactly
this reason, and a non-static definition in a header is ill-formed the moment
two translation units include it. Widening it here would be a change nothing in
this ticket exercised.

Forward references are also unchanged: the header walk is a single pass, so a
bodied static that calls something declared *later* in the same header is not
newly supported. It was not supported before either — it produced a broken
binary instead of an error — so nothing regresses, but the limit is real and
undocumented until now.

## Log
- 2026-08-29 — filed by pxx-a5, split out of the unit-resolution ticket.
- 2026-08-30 — reproduced at HEAD before claiming (all three cells), then fixed.
- 2026-08-30 — resolved, commit PENDING-COMMIT.
