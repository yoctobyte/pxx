---
slug: bug-c-a-header-reached-by-uses-discards-function-bodies-and-imports-them-instead
track: C
type: bug
prio: 55
status: backlog
found: 2026-08-29
found-by: pxx-a5
summary: "A `static`/`static inline` function DEFINED in a .h reached through `uses` has its body discarded and becomes an external, so the program links a DT_NEEDED on a lib<header>.so that does not exist and dies at load. The identical function in a .c compiles and runs. Discovered while fixing bug-a-a-c-include-path-captures-a-pascal-uses; it is the OTHER half of that ticket's silent arm and survives its fix."
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
