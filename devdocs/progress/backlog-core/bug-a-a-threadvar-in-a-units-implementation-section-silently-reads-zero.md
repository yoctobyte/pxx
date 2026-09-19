---
slug: bug-a-a-threadvar-in-a-units-implementation-section-silently-reads-zero
title: "a threadvar declared in a unit's IMPLEMENTATION section silently reads 0; the same declaration in the INTERFACE works"
type: bug
track: A
prio: 55
status: new
created: 2026-09-19
found-by: frankS
tags: [threadvar, tls, units, silent-wrong-value, x86-64]
blocked-by: []
summary: "A `threadvar` declared in a unit's IMPLEMENTATION section is given storage but never rewritten into a per-thread access, so every read returns 0 and every write is lost — with NO diagnostic. Moving the identical declaration to the unit's INTERFACE makes it work. Measured 2026-09-19: a unit with `threadvar counter: LongInt;` in its implementation plus `Bump` (counter := counter + 7) and `Got` answers `got=0`; the same unit with the threadvar in the interface answers 7, and a threadvar in the MAIN program answers 7. REPRODUCES ON THE PINNED COMPILER, so it predates the 2026-09-18/19 TLS work entirely. Storage IS allocated in both spellings — 385 Int64 threadvars in an implementation section hit the 3072-byte cap exactly as they do in an interface section — so this is not the allocator. The AST at CompileAST time is IDENTICAL for the two spellings (both `AN_IDENT ival=308`, dumped with PXXDBG=a.ast:Bump, which prints above the rewrite), so the divergence is at or after ThreadVarRewriteRange: the question is whether SymTlsOffset is still >= 0 for the symbol the unit's procedure actually BINDS to. Prime suspect is that the implementation-scope symbol the body resolves to is not the one the `threadvar` section gave an offset to."
---

# The measurement

Three spellings, one behaviour each, all with `--threadsafe` on x86-64:

| where the `threadvar` is declared | `got=` |
| --- | --- |
| main program | **7** — correct |
| unit INTERFACE | **7** — correct |
| unit IMPLEMENTATION | **0** — wrong, silent |

```pascal
unit tvunit;
interface
procedure Bump;
function Got: LongInt;
implementation
threadvar counter: LongInt;          { move this line above `implementation` and it works }
procedure Bump; begin counter := counter + 7; end;
function Got: LongInt; begin Result := counter; end;
end.
```

with `program usetv; uses tvunit; begin Bump; writeln('got=', Got); end.`

**Reproduces on the pinned compiler**, so it is not fallout from the threadvar-area
knob work of 2026-09-18/19 and no bisect of that range will find it.

# What it is NOT — measured, so nobody re-walks these

- **Not the allocator.** 385 `Int64` threadvars (3080 bytes) in a unit's
  IMPLEMENTATION section are refused by the 3072-byte cap, exactly as the same
  385 are in an INTERFACE section. Both spellings consume the area, so both
  reach `TryAssignThreadVarStorage` and both get offsets.
- **Not the parse.** `PXXDBG=a.ast:Bump` prints an IDENTICAL tree for the two
  spellings — same kinds, same `ival=308`. Note the dump sits ABOVE
  `ThreadVarRewriteRange` in `CompileAST`, so an unrewritten `AN_IDENT` there is
  expected in both and the dump cannot separate them. It rules the parser out,
  nothing more.
- **Not the area being too small.** The using program has a `uses`, so it gets
  the full default area under every setting.

# Where to look

`ThreadVarRewriteRange` (`ir_codegen.inc`), called per body from `CompileAST`.
Its whole test is `SymTlsOffset[sym] >= 0` for each `AN_IDENT`. Two candidates,
and the first is the likelier:

1. **The body binds to a different symbol than the one that got the offset.** An
   implementation-section declaration may enter a scope that is re-created or
   shadowed before the procedure bodies below it are compiled, leaving the body's
   `AN_IDENT` pointing at a twin whose `SymTlsOffset` is still -1. That produces
   exactly this: storage allocated, reference not rewritten, access lowered as an
   ordinary global, reads 0.
2. **`ThreadVarRewriteHigh`'s watermark.** It records how far into the PERMANENT
   AST region the sweep has got, and `pasparser_decl.inc` raises `ASTArenaFloor`
   at declaration time. If an implementation-section declaration moves the floor
   differently from an interface one, the watermark can carry the sweep past
   nodes that still need it. The routine's own comment records a one-statement
   bug from assuming the watermark was a high-water mark of `ASTNodeCount`.

# Why the prio is 55

It is a SILENT WRONG VALUE in a feature that exists for concurrency, and the
wrong value is the type's zero — which reads as "not yet set" rather than as a
fault, so the first suspicion falls on the program's own logic. The spelling that
breaks is also the more natural one: a `threadvar` that is private to a unit
belongs in its implementation section, and putting it in the interface to make it
work is the opposite of what a reader would choose.

No fixture covers it: all four `threadvar` fixtures in `test/` declare theirs in
the MAIN PROGRAM, which is the one spelling that works.

# Not related to the area knob

`-dPXX_TLS_USER_*` and the flag-free prescan added 2026-09-19 are independent:
a program with a `uses` keeps the full default area, which is what this test
program gets. Fixing this does not need either, and neither caused it.
