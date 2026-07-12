---
prio: 60
---

# _Generic cannot tell `long` from `int` on ILP32 (silent wrong selection)

- **Type:** bug (correctness — silent wrong branch, no diagnostic)
- **Track:** C — C frontend (`cparser.inc`); tag: compat
- **Status:** backlog — opened 2026-07-12.
- **Owner:** —
- **Surfaced by:** tstate `test-c-conformance-{i386,arm32,riscv32}#shard2,5` — `00219.c`.

## Symptom
On every **ILP32** target (i386 / arm32 / riscv32), `_Generic` picks the `int`
association where C requires `long`:

```c
long l = 5;
_Generic(17L, int:1, long:2, long long:3)   /* -> 1, must be 2 */
_Generic(l,   int:2, long:1)                /* -> 2, must be 1 */
```

x86-64 and other LP64 targets pass, because there `long` is 64-bit and so already
has a distinct TTypeKind (tyInt64 -> cgLong).

**Not an ordering artefact to be dismissed:** `_Generic(l, long:1, int:2)` happens
to return the right answer purely because the `long` association is listed first.
Reversing the associations exposes it. `00219.c` only shows ONE diff line for the
same reason — the other `long` cases are masked by association order.

## Root cause
`CGScalarKindOfTk` (cparser.inc ~417) derives the _Generic type descriptor from
`TTypeKind` alone, and maps `tyInteger`/`tyInt32 -> cgInt`, `tyInt64 -> cgLong`.
On ILP32 a C `long` IS 32 bits, so both `int` and `long` land on tyInt32 and the
descriptor collapses them. The width is right (`sizeof(long) == 4`); it is the
C-level *type identity* that is lost.

The `L`-suffix path has the same hole from the other side: the literal typing at
cparser.inc ~619 promotes an `L` literal to tyInt64 only when `TARGET_PTR_SIZE = 8`,
which is correct for width and wrong for identity.

The `cgXxx` layer exists precisely to model distinctions TTypeKind collapses (its
own header comment says "must distinguish long from long long"). It just is not
fed a long-ness bit on ILP32.

## Shape of the fix
Carry C `long`-ness independently of width, and consult it only in the _Generic
layer (C-mode only; the Pascal self-host never reaches this code):
1. a per-symbol flag set when a C declaration's base type was `long` (not `long long`);
2. a per-literal flag from the lexer's existing `CAttrFlags` bit 16 (it is already
   recorded — see clexer.inc ~605 — and then thrown away on ILP32);
3. propagation through the usual arithmetic conversions for `i + 2L` (00219.c
   asserts that this yields `long`), i.e. int-rank + long -> long.

Do NOT "fix" this by re-mapping `long` onto the other 32-bit TTypeKind
(tyInteger vs tyInt32): they are used interchangeably across the compiler and the
ABI is identical, so that would be a silent trap for the next reader.

## Repro
```
compiler/pascal26 --target=i386 t.c /tmp/t && /tmp/t
tools/testmgr.py --tier full --job 'test-c-conformance-i386#shard2/6'
```

## Note on the tstate attribution
tstate blames `96b6bac331d9` ("fix(tickets): Blocked-by bullet takes bare slugs"),
a **prose-only commit that cannot change codegen**. The bisect is bogus; this is a
long-standing GAP that the conformance job newly covers, not a regression. Do not
revert anything on the strength of that attribution.

## Gate
C tests green + self-host byte-identical + cross (all four ILP32 targets).

## Log
- 2026-07-12 — opened; root-caused to CGScalarKindOfTk collapsing long/int on ILP32.
