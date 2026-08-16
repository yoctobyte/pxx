---
summary: "a routine-local typed const gets a stack slot re-initialised from the prologue, so the `const calls: Integer = 0; Inc(calls)` counter idiom prints 1 forever; string-typed ones do not compile at all. FPC's are static."
type: bug
prio: 50
track: P
---

# A routine-local typed const is re-initialised on every call

- **Type:** bug (Pascal frontend — `ParseConstSection` in `compiler/parser.inc`,
  plus symbol-table support). Track P / shared core.
- **Status:** done (2026-08-16, same session that filed it).
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

## What landed

The **storage** half of the reverted attempt was fine and was kept:
`AllocStaticLocal` makes `AllocVar`/`AllocArray` place a routine-local typed
const in BSS while it keeps its routine BlockId (so it stays visible only inside
the routine), and a `SymStaticLocal` parallel array exempts it from the
decl-order gate, which only makes sense for file-scope globals.

The **initialiser** half was replaced with the C frontend's shape: rows are
tagged `LocalInitStatic`, and `CompilePendingLocalInits` now runs in two passes
— ungated for `var x: T = init` (which must re-initialise per call, and is the
control in the test), then the const rows collected into one chain emitted as
`if guard = 0 then begin guard := 1; <inits> end` over a hidden BSS int. Nothing
outlives the routine's parse, so `SymRollbackTo` is irrelevant.

## Residuals, both pre-existing and both confirmed at GLOBAL scope too

- A typed **string** const is a read-only string-literal alias with no storage
  (`ParseConstSection` says so and gives the reason), so `s := s + 'c'` is
  `undefined variable (s)` — identically for `const s: string[8] = 'ab'` at unit
  scope. Not local-specific, so not this ticket.
- A local const whose name matches its own **nested** routine binds the
  routine's mangled name (`undefined variable (Inner$13)`) — filed as
  [[bug-p-a-const-named-like-its-nested-routine-binds-the-routine]]. Confirmed
  identical on the pinned binary.

## Gate

The table above, as `test/test_local_typed_const_is_static.pas` with FPC's
column as `.expected`; `gate.sh quick`; self-host fixedpoint (the compiler's
own sources contain local typed consts, which is what caught the first
attempt).

