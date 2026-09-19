---
slug: bug-a-a-threadvar-in-a-units-implementation-section-silently-reads-zero
title: "THE SLUG IS WRONG: the unit's implementation section was never the variable -- a FUNCTION that reads a threadvar is retained by the -O2 inliner as a plain GLOBAL read, and then faults or reads zero"
type: bug
track: A
prio: 70
status: done
created: 2026-09-19
found-by: frankS
tags: [threadvar, tls, units, silent-wrong-value, x86-64]
blocked-by: []
summary: "FIXED. The section was never the variable and neither was the unit: what decides the outcome is whether the routine reading the threadvar is a FUNCTION small enough for the -O2 inliner to RETAIN. A threadvar symbol is `skGlobal`, and at retention time its reference is still a plain AN_IDENT -- ThreadVarRewriteRange runs from CompileAST, which pasparser_proc.inc:3654 calls AFTER TryRetainInlineBody -- so InlineExprSimple's global arm accepted it and CloneToInlineRegion copied a PLAIN GLOBAL read into the permanent inline region. `PXXDBG=a.inline` said it in one word: `RETAIN F shape=1 params=0 readsGlobal`. TWO SYMPTOMS, ONE CAUSE: a body retained BEFORE the first rewrite was then swept by it -- the sweep started at node 0, inside the inline reserve -- and its address node came from AllocNode, the VOLATILE arena that is rolled back per statement, so the call site read a recycled node and SEGFAULTED; a body retained AFTER that first sweep was never swept and read the threadvar's unused BSS slot, i.e. ZERO, silently. It is a DEFAULT-`-O` defect: -O0 and -O1 were correct throughout, which is also why every existing threadvar fixture passed -- all four read their threadvars from the main body or through a procedure, and a procedure is not a retention candidate. Fixed at the retention door (InlineExprSimple refuses an ident whose SymTlsOffset >= 0, above the kind dispatch) plus a clamp keeping ThreadVarRewriteRange out of [0..INLINE_AST_RESERVE) entirely, so a permanent parent can never point at a volatile child. The two halves fail DIFFERENTLY on purpose. Cost: a threadvar read is a real call at every -O, as it already was at -O0/-O1. Guarded by test_tvinline26, twelve rows, born red on the pin and on HEAD before the fix."
owner: frankS
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

# Why prio 70 and not the 55 it was filed at (2026-09-19)

Argued up by frankuser and I agree, with ONE correction to the premise, because
the corrected version is the stronger argument and the uncorrected one would be
quoted back at me.

**The premise I do not accept as stated:** *"it reproduces on the pin, so every
`$(PXX_STABLE)` consumer has it today."* True about the compiler and currently
VACUOUS about impact — counted 2026-09-18 while building route A's `uses` guard,
**no unit under `lib/` or `compiler/builtin/` declares a threadvar at all**, in
either section. There is no consumer to be wrong today. Ranking this on installed
blast radius would be ranking a population of zero.

**What actually raises it, and it is the goal list, not the byte count:**
`threading` is a named, unowned gap — a module real programs import and which
does not exist here. A per-thread counter in a unit's IMPLEMENTATION section is
not an edge case on that path, it is the SHAPE that module is written in: the
state is private to the unit, which is exactly what an implementation section is
for, and the interface spelling that happens to work is the one a careful author
would reject as leaking internals. So the defect sits ON the road to the work,
pointing at the more natural spelling, and it is silent. That is worth 70.

**And the class is the expensive one here regardless of population:** the wrong
value is the type's ZERO, which reads as "not initialised yet" rather than as a
fault, so suspicion falls on the program's own logic first and the compiler is
the last place anyone looks. A diagnostic would make this a 30.

Not raised higher because nothing in the tree is blocked on it right now and no
umbrella names it; it is a bug to fix before the threading work, not before the
next pin.


# What it actually was (2026-09-19, and it corrects this ticket's own slug)

Everything in the sections above is a correct measurement and the CONCLUSION
drawn from it was wrong, so it is left standing rather than edited: the table of
three spellings is real, and the reason the interface row read 7 while the
implementation row read 0 is not the section at all. Both readers were compiled
in one run; one of the two functions happened to be retained by the inliner
before the first rewrite and the other after it. **The census was built on the
hypothesis it was testing** -- three spellings of WHERE the declaration sits,
when the axis that decides is WHAT READS IT.

The axis nobody varied is the reader. Varying it takes one extra row:

| the reader | result |
| --- | --- |
| the main program body, directly | correct |
| a PROCEDURE, through a var parameter | correct |
| a FUNCTION returning it | **0, or a fault** |

and the same function is correct at `-O0` and `-O1`. That is the whole bug:
`TryRetainInlineBody` runs at `-O2` and above.

**Why every existing fixture passed.** All four threadvar fixtures read their
threadvars from the main program body or through a procedure -- the two
arrangements that work. Not one wrapped a read in a function, which is the
ordinary way for a unit to expose per-thread state. This is CLAUDE.md's rule
about the interesting element's POSITION arriving on a new axis: the population
everyone writes is not an ORDER of elements here but a CHOICE OF READER, and the
choice everyone made is the one that passes.

**What ruled out the parser and the allocator was correct and useless.** The AST
dump was identical for the two spellings because the AST *is* identical; the
divergence is in a CLONE taken elsewhere, at a different time, by a subsystem
neither instrument looks at. `PXXDBG=a.inline` names it in one line and cost
nothing -- it was simply not on the list of things being asked. The lesson is
not "dump more": it is that both instruments answered about the tree the
compiler was lowering, and nothing asked what else had already been copied out
of it.

# The fix

`compiler/inline_expand.inc`, `InlineExprSimple`, above the kind dispatch:

```pascal
if SymTlsOffset[idx] >= 0 then Exit;
```

Above the dispatch and not inside the `skGlobal` arm, so the refusal does not
depend on a threadvar continuing to be `skGlobal`.

`compiler/ir_codegen.inc`, `ThreadVarRewriteRange`: the sweep now starts at
`INLINE_AST_RESERVE` and never banks below it. The inline reserve is permanent
and `AllocNode` is not, so a rewrite in that region mints a volatile child for a
permanent parent -- the dangling reference the fault came from.

# What is NOT fixed, and it is a decline rather than a gap

A threadvar read costs a real call at every `-O`, as it already did at `-O0` and
`-O1`. The rewritten form -- `AN_DEREF` of `AN_TLSBASE`, a base-plus-constant
load -- is perfectly inlinable, and retaining it means rewriting BEFORE
retention and minting the address node with `AllocInlineNode` so it is
permanent. That is a change to the ordering this subsystem is built on
(`pasparser_proc.inc` retains at :3654 and compiles at :3666) and it wants its
own measurement and its own ticket, not a second edit smuggled into a bug fix.
Nothing under `lib/` or `compiler/builtin/` declares a threadvar, so the present
cost is zero everywhere except inside a program that uses the feature.

## Log
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
