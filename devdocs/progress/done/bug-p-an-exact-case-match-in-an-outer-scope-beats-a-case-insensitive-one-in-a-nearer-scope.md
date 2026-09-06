---
track: P
prio: 55
type: bug
blocked-by: []
status: done
owner: frankB
created: 2026-09-06
found-by: frankB
summary: "A local or parameter referenced with a DIFFERENT CASE from its declaration silently resolved to an outer symbol of the same name. `procedure Bump(Counter: Integer); begin counter := 55; end;` wrote the GLOBAL and left the parameter at 7, where fpc 3.2.2 writes the parameter; reads, writes and by-ref intrinsics alike, no diagnostic, and `--strict-case` did not fire. FIXED 2026-09-06 (frankB): `FindSym` made TWO FULL WALKS of the hash chain, exact-case then case-insensitive, which ranked case-exactness ABOVE scope depth; it is ONE walk now and the second is DELETED as strictly implied. THE SHAPE THIS TICKET FIRST PROPOSED (per-block, innermost out) IS WRONG AND WAS MEASURED WRONG: `SymBlockId` models only --lazy-var begin/end blocks, so a parameter and a program global share one block. What makes the single walk correct is `SymRollbackTo`, which unhashes a routine's symbols at its exit, so the chain holds only in-scope symbols and its newest-first order IS scope depth. NilPy stays safe (`SymCaseSensitive` disables the second disjunct for a NilPy user's own names). THE OLD ORDER WAS MASKING TWO FILES OF OUR OWN: `compiler/builtin/pyeval.pas` (a local `cur` beside the unit's `Cur`, a parameter `src` beside the unit's `Src` -- uforth died until both were renamed) and `lib/rtl/strutils.pas`, which declares a PARAMETER `N` and a LOCAL `n` in one routine three times, which fpc rejects outright. A corpus-wide sweep flagged 13 files; three were real, the `Pos -> pos` group is benign and was checked rather than assumed."
---

# An exact-case match in an outer scope beats a case-insensitive one in a nearer scope

Measured 2026-09-06 at compiler `b50b1643e1a8` against fpc 3.2.2. Found while
probing an unrelated accessor ablation; **no ticket led here.**

```pascal
program shadow4;
var counter: LongInt; ok: LongInt;
procedure Bump(Counter: Integer);
begin
  counter := 55;      { the lower-case spelling of the PARAMETER Counter }
  ok := Counter;      { must read 55 }
end;
begin
  counter := -1; ok := 0;
  Bump(7);
  WriteLn('global counter=', counter, ' seen=', ok);
end.
```

| | global `counter` | `ok` (the parameter) |
| --- | --- | --- |
| **pxx** | **55** | **7** |
| fpc 3.2.2 | -1 | 55 |

Both halves are wrong and they are wrong in opposite directions: the global is
corrupted and the parameter keeps its old value. **Silent** — no diagnostic, and
`--strict-case` does not fire on it either (measured: the program above compiles
clean under the flag).

## The boundary, which is what names the mechanism

| shape | pxx | fpc |
| --- | --- | --- |
| same-case reference to a parameter | parameter | parameter |
| **different-case reference to a parameter** | **outer** | parameter |
| **different-case reference to a LOCAL** | **outer** | local |
| `Inc(counter)` on a parameter `Counter` | increments the outer | increments the parameter |
| different-case, **no exact-case match anywhere** (global `COUNTER`, local `Counter`, reference `counter`) | local | local |

The last row is the control. It is the case where the exact pass finds nothing,
so the case-insensitive pass runs and the ordinary innermost-first walk gives the
right answer — which is why this is not "pxx folds case wrong" but specifically
"pxx ranks case-exactness above scope depth".

A `for I := 1 to 3` over a local `i` also works, for the same reason: no outer
`i` exists to win the exact pass.

## Cause

`FindSym` (`compiler/symtab.inc`, ~4827) walks the hash chain twice:

1. `StrEqual` (exact) over the whole chain, and
2. `CaseEqual` over the whole chain, for `not SymCaseSensitive[i]` symbols.

**Its own comment says what it means to do and does not:**

> *Exact-case match first, innermost scope out (preserves shadowing). ... Hash
> chain is NEWEST-first, so walking it is the linear downto order.*

Innermost-first is true WITHIN a pass. Across the two passes it is false, and
shadowing is exactly what the structure gives up: an exact match in the outermost
scope beats a case-insensitive match in the innermost one. Per CLAUDE.md's
comment-vs-code rule, one of the two is wrong and here it is the code — the
comment states the Pascal rule correctly.

## Why the obvious one-pass fix is not the fix

Merging the passes into `exact or (CaseEqual and not SymCaseSensitive[i])` lets
chain order alone decide, and chain order is DECLARATION order, not scope depth.
That is right for Pascal and wrong for NilPy, where `SymCaseSensitive` exists
precisely because `Foo` and `foo` are two different symbols in one scope and the
exact one must win regardless of which was declared later.

The shape that satisfies both is to make the passes **per enclosing block,
innermost outward** — exact then case-insensitive within each block before
moving out — rather than exact-everywhere then insensitive-everywhere. That is a
restructure of the walk, which is why this is a ticket and not a microfix.

## Gate

The five boundary rows above as one fixture, byte-identical to fpc; plus
`tools/run_fgl_corpus.sh` and the conformance suite, because this changes name
resolution for every program and the failure mode is a silently different symbol
rather than an error.

## Neighbour

[[bug-p-strict-visibility-is-silent-on-records]] is the other case of a
resolution-time rule that is opt-in and covers less than its name suggests.

## Fixed 2026-09-06 (frankB), compiler `6a676f92b94d`

`FindSym` is ONE walk now:

```pascal
    if (StrEqual(Syms[i].Name, lo) or
        ((not SymCaseSensitive[i]) and CaseEqual(Syms[i].Name, lo)))
       and IsBlockVisible(SymBlockId[i], CurBlockId) and SymBindableHere(i) then
```

The second walk is DELETED rather than kept: its predicate is strictly implied
by this one's second disjunct under identical gates, so it could not fire. The
four copies of the gate expression became `SymBindableHere` — they were only ever
correct identical, and the decl-order arm alone reads five columns.

### The shape this ticket proposed is wrong, and it was measured wrong

The body above says the fix is "per enclosing block, innermost outward". **It is
not**, because `SymBlockId` does not model routine scope: the only writer of
`CurBlockId` is `ParseBlockAST`, which allocates a block per `begin ... end` and
only when `--lazy-var` is on. A routine's parameters and locals are registered
with the ENCLOSING block's id, so a parameter and a program global sit in the
same block and a per-block walk changes nothing. Built and run: the fixture still
failed 7 rows.

**What actually makes the single walk correct is `SymRollbackTo`.** It UNHASHES
every symbol a routine declared when that routine exits, so the chain contains
only symbols genuinely in scope — and since inner scopes register after the outer
ones they shadow, the chain's newest-first order IS scope depth. That is the fact
the old comment was reaching for, and it lives one function away from the walk
that depends on it.

### NilPy was the right fear and the wrong diagnosis

The obvious merge was tried first and broke uforth (`pyeval: invalid assignment
target`), which read as "the two walks were protecting `SymCaseSensitive`". They
were not. A temporary print of every binding the new disjunct changed named the
whole population in one compile — **two names**:

```
NEWBIND Cur -> cur  kind=skLocal  line=4453 4463 4464 4482 4500
NEWBIND Src -> src  kind=skParam  line=2907 2926
```

Both in `compiler/builtin/pyeval.pas`, and both REAL Pascal collisions:
`DoAssignment` declares a local `cur: Variant` and then reads `TkText[Cur]`
meaning the unit's `Cur: Integer` token cursor; `pyclosure_src_new(const params,
src)` saves and restores the unit's `Src: AnsiString` as `sSrc := Src`, which
under correct scoping is the PARAMETER — so it restored the interpreter's source
buffer to the closure's body text. Renamed to `curV` and `srcText`; uforth then
ran under the merged walk too, and the narrowed `Kind <> skGlobal` variant that
had been written to dodge the problem was dropped as an unnecessary special case.

### What the old order was masking, and it is the reason this change is bigger than its diff

A corpus-wide sweep with that instrumentation — every Pascal source under the
test and examples trees — flagged **13 files**, of which the fixture itself is
one:

- **`compiler/builtin/pyeval.pas`** — the two above.
- **`lib/rtl/strutils.pas`** — `WordPosition`, `ExtractWordPos` and
  `ExtractDelimited` each declare a **PARAMETER `N` and a LOCAL `n`** and read
  them as two variables. **fpc rejects that outright as a duplicate identifier**;
  pxx accepted it and the two-walk order was the only thing keeping the two
  apart. Locals renamed to `sLen`.
- **`Pos -> pos`, five TLS/https devtests** — BENIGN, and checked rather than
  assumed. `lib/rtl/truststore.pas` has a local `pos: Integer` and calls the RTL
  `Pos()`. FindSym answers with the local, and the CALL path does not use that
  answer: a probe with the same shape prints `Pos=2` under pxx, and fpc refuses
  the program outright (`Syntax error, ";" expected but "(" found`). Us accepting
  what fpc rejects is not a defect, and nothing was changed there.
- The rest (`maxlongint -> MaxLongInt`, `my_thing -> MY_THING`, `stderr ->
  StdErr`, `S -> s`) are the same entity spelled two ways; every one of those
  tests is GREEN.

**Neither file was made wrong by this fix. Both were already wrong** and the
old walk order was the only thing making them work.

### Gate

`gate.sh quick` GREEN including the FPC seed canary; `run_fgl_corpus.sh` 7/7;
uforth compiles and evaluates (`3 3`); the five corpus tests whose bindings
changed and the two `lib/rtl/strutils` tests all GREEN; and the neighbour
Makefile job either side of the new row was run, not just the new row.

### Follow-on, not done here

pxx should REFUSE a parameter and a local that differ only in case, the way fpc
does — that is what would have caught `strutils.pas` at its declaration instead
of at a name lookup three functions later. Filed as
[[bug-p-a-parameter-and-a-local-that-differ-only-in-case-are-two-symbols]];
not landed with this change because a refusal is a narrowing over a population
nobody has enumerated, and this commit already moves name resolution.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
