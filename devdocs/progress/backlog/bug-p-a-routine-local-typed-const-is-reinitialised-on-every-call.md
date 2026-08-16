---
summary: "a routine-local typed const gets a stack slot re-initialised from the prologue, so the `const calls: Integer = 0; Inc(calls)` counter idiom prints 1 forever; string-typed ones do not compile at all. FPC's are static."
type: bug
prio: 50
track: P
---

# A routine-local typed const is re-initialised on every call

- **Type:** bug (Pascal frontend — `ParseConstSection` in `compiler/parser.inc`,
  plus symbol-table support). Track P / shared core.
- **Status:** backlog — **diagnosed, one attempt made and reverted**; the fix
  needs the C frontend's existing pattern rather than the one I tried. WIP diff
  parked at the bottom.
- **Found:** 2026-08-16, Pascal oracle sweep vs `fpc -O- -Mobjfpc` (typed
  constants topic). Confirmed **pre-existing** against the pinned binary, so it
  is not fallout from that day's const-expression work.

## Symptom

FPC gives a routine-local typed const **static** storage, initialised once —
that is what makes the counter idiom work. pxx gives it a stack slot and
re-runs the initialiser from the prologue:

| local const | FPC (3 calls) | pxx |
| --- | --- | --- |
| `const n: integer = 0; Inc(n)` | `1 2 3` | `1 1 1` |
| `const d: double = 1.5; d := d * 2` | `3.00 6.00 12.00` | `3.00 3.00 3.00` |
| `const b: boolean = false; b := not b` | `TRUE FALSE TRUE` | `TRUE TRUE TRUE` |
| `const c: char = 'a'; c := Succ(c)` | `b c d` | `b b b` |
| `const arr: array[0..2] of integer = (1,2,3); Inc(arr[0])` | `2 3 4` | `2 2 2` |
| `const s: string[8] = 'ab'; s := s + 'c'` | `abc abcc abccc` | **does not compile** — `undefined variable (s)` |

Silent for every ordinal/float/array case. The existing comment in
`ParseConstSection` states the behaviour as if it were the design ("compiled
into that routine's prologue so its stack-resident table is re-initialized on
each call"), which is why it survived: it reads as intentional.

## Why the obvious fix does not work — and what does

**Attempt (reverted):** force BSS storage inside a routine (`AllocStaticLocal`
honoured by `AllocVar`/`AllocArray`, symbol keeps its routine BlockId so it
stays locally visible, decl-order gate exempted via a `SymStaticLocal` parallel
array) and record the initialiser into `PendingInit` — the global path, emitted
once before `main begin`.

Storage and visibility both worked. **The initialiser did not**: leaving a
routine calls `SymRollbackTo(savedSC)`, which truncates every symbol the body
allocated. The `PendingInit` record then names an index past `SymCount`, and
the whole-program IR validation rejects it —
`invalid IR symbol reference in store_sym`. Self-host fails the same way at
`compiler.pas`. Any design that defers a *reference to a local symbol* past the
end of the routine hits this.

**What to do instead — the C frontend already solved it.** `static int x = 0;`
inside a C function has exactly these semantics and works today:
`CLocalStaticDecl` puts the storage in BSS, and `CWrapStaticInitOnce`
(`cparser.inc`) leaves the initialiser **inline in the body**, wrapped in
`if guard = 0 then begin guard := 1; <inits> end` over a hidden BSS int. No
symbol outlives the routine's parse, so the rollback is irrelevant.

For a *local* const the guard is not even observably different from FPC's
load-time init: the const is only visible inside its own routine, so the first
read cannot precede the first call.

Remaining piece: the string-typed case, which today is not merely mis-scoped
but undeclared (`undefined variable (s)`) — check whether BSS storage alone
fixes it or whether the managed-string init path needs the same treatment.

## Gate

The table above, as `test/test_local_typed_const_is_static.pas` with FPC's
column as `.expected`; `gate.sh quick`; self-host fixedpoint (the compiler's
own sources contain local typed consts, which is what caught the first
attempt).

## Parked WIP

The reverted attempt is a 164-line diff over `defs.inc` / `symtab.inc` /
`parser.inc` (the `AllocStaticLocal` + `SymStaticLocal` half is reusable; the
`PendingInit` half is the part that cannot work). It was left out of the tree
deliberately rather than parked in `unfinished/`, since a half-applied
compiler change is exactly what that directory's Track A rule warns about.
Re-derive from this write-up — it is shorter than the diff.
