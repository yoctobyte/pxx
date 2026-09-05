---
prio: 45
track: P
summary: "FIXED 2026-09-06, and it was THIRTEEN sites, not two. The ticket's own diagnosis was right — the intrinsic var-argument path resolves its destination by a route that does not know the own-name-is-Result rule — and understated the population. Probed: fpc accepts the own name for Str, Val, New, GetMem, Include and ReallocMem; pxx refused five of the six. THE RULE WAS ALREADY EXTRACTED as OwnNameResultSym, for the ONE caller that hit it (`Inc(FuncName[0])` in FPC cutils.pas); twelve other sites each spelled their own FindSym-then-ParseLValueAST and agreed with each other perfectly. One shared ParseIntrinsicDestLValue now owns all thirteen. GetMem was the one that already worked, because it takes its destination through ParseExpr and so never had a copy to be wrong. fpc's tstunits/erroru.pp compiles and runs byte-identical to fpc; tstring2 and tstring5 pass and their skip rows are deleted; the erroru clause is retracted from tstring4's and tobject1's."
---

# A function's own name is not an lvalue to `Str` and `Val`

- **Type:** bug — Track P (Pascal frontend)
- **Status:** done
- **Found:** 2026-09-05 (frankB), unblocking the conformance `erroru` trio

## Repro

```pascal
program o2;
function G: string; begin Str(7, G); end;
begin WriteLn(G); end.
```
`error: undefined variable (G)`

## The boundary — measured, and it moved the diagnosis twice

| shape | result |
| --- | --- |
| own name to a USER `var` parameter — `Fill(G)` | **works**, prints `x` |
| own name to `Str` — `Str(7, G)` | **refused** |
| own name to `Val` — `Val('7', G)` | **refused** |
| `Result` to a user `var` parameter | works |
| `Result` to `Str` | works, prints `7` — **the workaround** |
| own-name read/write with no var argument at all — `G := G + 'b'` | works |

Two readings had to be discarded to get here, and both are worth recording
because both looked settled:

1. **"It is a NESTED function problem."** The first sighting was
   `undefined variable (getsize$50501)` — a mangled nested name — inside
   erroru.pp's nested `getsize`. But a nested function reading and writing its
   own name with no `Str` works fine, and a TOP-LEVEL function with `Str` fails.
   The mangling in the message is what made nesting look causal; it is only
   telling you which scope the lookup happened in.
2. **"A function's own name is not an lvalue."** Also false — it is one, to a
   user procedure's `var` parameter, in the same program.

## Why it matters beyond the shape

This is the last thing between us and FPC's `erroru.pp`, the helper unit behind
**five conformance skip rows** (`tobject1`, `tstring2`, `tstring5` and two
more). Its recorded blockers — `ExitCode`, `System.ErrorAddr`,
`TFPCHeapStatus`, `GetFPCHeapStatus` — are all resolved as of 2026-09-05
(`ExitCode` had in fact been present for a while and the skip prose was stale).
`erroru.pp` now reaches its `getsize` helper and stops there, on this and
nothing else.

## Where to look

The general lvalue path already gets this right, so the fix is almost certainly
to route the intrinsic's destination argument through the same resolution rather
than to add own-name handling to a second place —
`devdocs/dev/normalise-dont-special-case.md` is the relevant north star, and
this is its stock shape: a construct reachable through two paths, where the
second path is the one that stayed broken. Grep for `Val` when fixing `Str`;
they fail identically and are presumably siblings in the same argument handler.

# RESOLVED 2026-09-06

## The population was six times the ticket

This ticket named `Str` and `Val`. Probing the CONSTRUCT — "an intrinsic that
writes through its destination argument" — against fpc 3.2.2:

| | fpc | pxx before |
|---|---|---|
| `Str(7, A)` | 7 | `undefined variable (A)` |
| `Val('7', B, c)` | 7 | `undefined variable (B)` |
| `New(C)` | 3 | `undefined variable (C)` |
| `GetMem(D, 8)` | 4 | **4 — already worked** |
| `Include(E, 'b')` | TRUE | `undefined variable (E)` |
| `ReallocMem(F, 16)` | 6 | `undefined variable (F)` |

**The row that worked is the one that decides the fix.** `GetMem` takes its
destination through `ParseExpr`, so it never had a copy of the resolution to be
wrong. Every refusing site had its own copy.

## The rule was already written down, and one caller knew

`OwnNameResultSym` (`pasparser_lval.inc`) has existed since somebody hit
`Inc(FuncName[0])` in FPC's `cutils.pas:1429`. **Exactly one of thirteen
possible callers was wired to it.** The other twelve each spelled:

```pascal
idx := FindSym(CurTok.SVal); identTokIdx := TokPos - 1; Next;
valNode := ParseLValueAST(idx, identTokIdx);
```

Twelve identical copies, all missing the same fact, all agreeing. `SetLength`
made fourteen: it carried its own inline restatement of the rule's four
conditions, written before the routine was extracted.

`ParseIntrinsicDestLValue` now owns all thirteen; `SetLength` delegates the rule
but keeps its own `FindVarSym` base lookup, which is documented on the spot —
a shared helper that took the wrong base lookup for one caller would be worse
than one that caller skips.

## The corpus march

`erroru.pp` compiles and runs byte-identical to fpc. Its five dependent
conformance rows, counted by grepping all 132 skipped sources for the unit
rather than by trusting this ticket's number:

- **`tstring2.pp`, `tstring5.pp`** — pass, output byte-identical to fpc. Skip
  rows deleted.
- **`tstring4.pp`** — compiles and runs; diverges only on `GetFPCHeapStatus`
  numbers. Its `wontfix` stands on its own merits; the erroru clause is gone.
- **`texception3.pp`** — compiles, runs, **passes all 119 exception sub-tests**,
  and fails only on a final allocator-introspection assertion. See below.
- **`tobject1.pp`** — held only by `decide-old-style-object-types` now. Its
  "double-blocked, also wants erroru" clause is retracted in place, with the
  instruction to re-measure rather than assume if the decision flips.

## The false reading I wrote down before controlling for it

`texception3` prints **`exception generates memory holes`**, and I put
"EXCEPTION HANDLING LEAKS" into `pxx.skip` on the strength of it.

The control — 100 `IntToStr`/concat iterations and **no exception anywhere** —
reports `Lost: 208 bytes` under pxx and `Lost: 64 bytes` under fpc. So
`DoMem <> 0` is a heap high-water reading and not a leak detector, **in either
compiler**. The pxx allocation census agrees: a 1000-iteration raise/handle loop
gives `allocs=1871 frees=1868 live=3`.

**A message printed by a test is a claim about the test's own model, not a
measurement** — and it carries the authority of FPC's own testsuite, which is
exactly what made it credible. Third coherent-but-false reading in two sessions,
and the first one caught before it shipped, by the habit banked hours earlier:
find the reading about a different substance.

Residual filed with an owner:
[[bug-b-currheapused-does-not-return-to-its-prior-value-after-a-freed-block]].

## Test

`test/test_own_name_is_the_result_to_every_intrinsic.{pas,expected}` — 10 rows,
fpc oracle. Row D is `GetMem`, green before the fix, present to say why the fix
is one function. Row G is `erroru.pp`'s own nested `getsize` shape. Rows H and I
are the two guards: a local named like the function still wins, and a following
`(` is a recursive call and not an lvalue.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
