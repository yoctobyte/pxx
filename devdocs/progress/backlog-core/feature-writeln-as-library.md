---
prio: 40
track: A
type: feature
status: backlog
summary: "PHASE 1 LANDED 2026-09-01: variadic bracket-elision -- `Log('x=', x)` against `procedure Log(const a: array of const)` now compiles, for BARE ROUTINE calls (procedure statement and function-in-expression). METHOD calls still require the brackets: they go through a signature-driven argument loop that never reaches the resolver this hooks, so `g.Log('a', 1)` is still `wrong number of parameters` -- that is the next slice. Phases 2 (`expr:w:p` via a vtFormatted tag) and 3 (the library write/writeln over array of const) are untouched. Do NOT replace the builtin writeln: compiler.pas self-hosts on it."
---

# write/writeln as a library function (via `array of const` + variadic sugar)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-16

## Motivation

The builtin `write`/`writeln` are special-cased in codegen (`IR_WRITE` /
`IR_WRITELN`) and are not fully FPC-compatible: no file handles, partial format
support, fixed stdout. Now that `array of const` (TVarRec) is a stable,
self-hosted feature — the compiler's own asm-text emitter consumes
`items[i].VType` on all targets, element tags (incl. `vtExtended` for floats)
live in `compiler/builtin/builtinheap.pas` — `writeln` can be expressed as an
ordinary **library** routine taking `array of const`, with a little syntactic
sugar to keep the familiar call shape.

The sugar is the real win: it makes ANY user-defined variadic routine ergonomic
(`Log(...)`, `Format(...)`, `Assert(...)`), not just writeln.

**Do NOT replace the builtin writeln.** The library version must coexist and be
opt-in until it is proven byte-identical; `compiler.pas` self-hosts on the builtin
(871-proc fixedpoint) and must not regress.

## The three pieces (dependency order)

### 1. Variadic bracket-elision (useful standalone)

At a call `f(a, b, c)` where `f` resolves to a routine whose last (or only)
parameter is `array of const`, and the arguments are not already a single
`[...]` literal, auto-wrap them into the TVarRec literal: `f([a, b, c])`. The
call-arg builder already constructs `AN_VARREC_ARRAY`; do the wrap in that one
place.

- **Ambiguity rule (non-strict, predictable):** the variadic form is a
  *fallback*. Only elide brackets when no non-variadic overload matches the given
  argument list; prefer an exact non-variadic match. This avoids surprises when a
  `writeln(s: string)` overload also exists.
- **Don't double-wrap** an already-bracketed call.
- This alone lets users write `Log('x=', x, ' y=', y)` against
  `procedure Log(const a: array of const)`.

### 2. `expr:w:p` formatting via a format element

Add a `vtFormatted` element tag (in `builtinheap.pas`) carrying the value, its
underlying type, a width, and a precision. The parser — **only inside a loosened
variadic argument list** — rewrites `arg : w [ : p ]` into a `vtFormatted`
element (the `:` is unambiguous in that position; it is where FPC parses
width/precision too). The library `writeln` reads the tag and formats. Floats
already box as `vtExtended`, so `x:0:2` on a Double works.

### 3. File handles

`writeln(f, ...)` where the first argument is a file/text value routes output to
its file descriptor instead of stdout. Phase it:

- First: stdout / stderr (a `TextFile`-typed first arg resolving to fd 1/2).
- Later: real file I/O — `TextFile`, `AssignFile`/`Reset`/`Rewrite`/`CloseFile`,
  buffering. This is where the current builtin is genuinely incomplete.

## Constraints / gotchas

- **Coexistence + opt-in:** keep the builtin as default; gate the library version
  behind a unit or define. No default flip until byte-identical parity is proven
  and `make` / `make cross-bootstrap` stay green.
- **Exact output parity:** newline/flush/line-buffering, integer and float
  formatting digits, boolean rendering (PXX currently prints `1`, FPC `TRUE` —
  decide and match). Validate against `test_conformance_*` and the cross suites.
- **Performance:** each library `writeln` boxes a TVarRec vector (heap alloc).
  Acceptable for normal use; note it for hot logging paths; consider a fast path
  for the trivial single-scalar case if it matters.
- **Managed strings:** the library `writeln` pulls in `builtinheap` (array of
  const already allocates) — already true for array-of-const programs.

## Suggested phasing

1. Variadic bracket-elision (generic; ship + test with a user `Log`).
2. `vtFormatted` tag + parser `:w:p` rewrite in variadic arg lists.
3. Library `write`/`writeln` to stdout/stderr in a unit, behind a define; prove
   output parity on the conformance + cross suites.
4. File-handle forms (`TextFile`, Assign/Reset/Rewrite).
5. Much later: consider making the library version the default, only after a
   byte-identical self-host + cross-bootstrap proof.

## Notes

- Element tags today: vtInteger 0, vtBoolean 1, vtChar 2, vtExtended 3,
  vtPointer 5, vtAnsiString 11, vtInt64 16 (`builtin/builtinheap.pas`). Add
  vtFormatted alongside.
- Related: the bracket-elision sugar is independently valuable — could land and be
  used for user variadics well before any writeln rewrite.

## Track B note (2026-07-20)

Listed in the Track B ready queue, but phases 1 and 2 — variadic bracket-elision
and `expr:w:p` formatting — are **parser work in `compiler/**`**, i.e. Track A/P,
not Track B. Track B cannot start this; only phase 3 (the library `write` /
`writeln` over `array of const`) is ours, and on its own, called with explicit
`[...]` brackets, it is a strictly worse `writeln` that nobody would use. The
value is in the sugar, and the sugar is the compiler's.

Left in backlog rather than blocked/, since it is not externally blocked — it
just needs the owning lane to be A/P for the first two phases. Whoever ranks
this should treat it as a Track A ticket with a Track B tail.

## Lane correction (2026-07-20)

Track re-labelled B -> A on 2026-07-20: phases 1 (variadic bracket-elision) and 2 (expr:w:p formatting) are parser work in compiler/**. Phase 3, the library write/writeln over array of const, is the only Track B part and in isolation is a strictly worse writeln nobody would call — the value is in the sugar, and the sugar is the compiler's.


---

## 2026-09-01 (frankH) — phase 1 landed for bare routines; methods are the next slice

**Track A.** `Log('x=', x, ' y=', y)` against `procedure Log(const a: array of
const)` now compiles. Verified absent before the change (*"no overload of Log
matches these arguments: (ShortString, Integer)"*), verified present after.

### Where it went, and why that placement is the whole design

**Not in the argument loop — in the `procIdx < 0` arm beside
`TryFillTrailingDefaults`**, in `pasparser_expr.inc` (function call in an
expression) and `pasparser_stmt.inc` (procedure call statement). Two properties
follow, and the second is worth more than the first:

1. **The ticket's ambiguity rule is free.** *"Only elide when no non-variadic
   overload matches; prefer an exact non-variadic match"* IS *"run after
   `MatchCallDelphiProcAddr` has already failed"*. It is enforced by placement
   rather than by a rule that can drift.
2. **It cannot change the meaning of any program that compiles today, by
   construction** — every call it can see is one that errors without it. The
   case that would otherwise be dangerous is `array of const` PASS-THROUGH
   (`Inner(a)` from inside `Outer(const a: array of const)`), which must stay a
   forward of the same vector and must never become `Inner([a])`. **Checked by
   running it, before and after:** it resolves, so `procIdx >= 0` and the
   elision is never reached. There is a row for it in the test that fails if
   the placement ever moves.

Slots are tried **largest-first** (most fixed parameters bound is the most
specific reading); each candidate is committed, re-resolved through the real
resolver, and rolled back on refusal. **Nothing in the new code decides whether
a call matches** — `MatchCallDelphiProcAddr` does, on a chain rewritten into a
shape it already understood. So a candidate scan that is too loose costs a
rejected retry, never a wrong bind.

### `MakeVarRecArrayFromArgs` — extracted, not duplicated

frankA's catch, and it was the real risk. There is exactly ONE place in the
compiler that constructs an `AN_VARREC_ARRAY`: `ParseVarRecLiteralAST`. But it
is a *parser* — `Expect(tkLBrack)`, loop, `Expect(tkRBrack)` — and at the
elision hook the arguments are already an AN_ARG chain with no brackets left to
consume, so it cannot be called. Hand-building the node there would have made
this the second construction site, which is what
`normalise-dont-special-case.md` is actually about.

So the four lines that decide what the node IS were pulled out into
`MakeVarRecArrayFromArgs(elemHead)` and both callers use it. They now differ
only in how they obtained the element chain.

### Gate, and both controls were RUN

`make compiler/pascal26` — **`converged after 1 round(s)`**, the recompute verb,
not the stamp. `tools/gate.sh quick` **GREEN**, with the FPC seed canary
**PASS** rather than SKIP (the tree still had uncommitted `compiler/**`, which
is the only condition under which that canary runs at all).

`test/test_variadic_bracket_elision.pas`, 14 rows, registered in `test-core`.
**The load-bearing rows are the `same-as-brackets` pairs** — they compare the
elided call against the explicitly bracketed call of the same routine, which is
what pins the two spellings to one builder. Everything else could be satisfied
by an elision that builds a subtly wrong node and still prints something.

| control | result |
| --- | --- |
| hook disabled (`procIdx := -1`) | the test file **does not compile**; recipe exits 1 |
| node hand-built without `TVarRecId` | **compiles cleanly**, prints `?` element tags, 6 rows RED |

The second is the one that matters: it is exactly the failure frankA predicted,
it produces no diagnostic at all, and it would have been invisible to every
test that existed before this one.

### The boundary — stated because it is not obvious from the feature's name

**Method calls are NOT covered.** `g.Log('a', 1, 2)` is still
`wrong number of parameters in call to TLogger.Log`. The method paths parse
arguments **driven by the signature**, slot by slot, and `ExpectCallRParen`
fires on the leftover tokens — so they never reach `MatchCallDelphiProcAddr`
and never reach this hook. Covering them means keeping parsing at the last slot
when that slot is `array of const`, across the ~6 method argument loops that
share `ExpectCallRParen`. That is a different mechanism in a different file and
it is the next slice, not an oversight.

**The NilPy sites are deliberately out of scope.** `MatchCallDelphiProcAddr`
has four call sites, not two: `pyparser.inc:49079` and `:49097` are the other
pair. Python has its own `*args` packing (`PyPackStarArgs`) and this is a
Pascal-surface feature, so they were left alone **on purpose** — recorded here
because the next person to touch elision will find four sites with two handled.

Phases 2 and 3 are untouched.
