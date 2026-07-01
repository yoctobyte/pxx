# Nested procedure can't call its sibling (and capturing self-recursion breaks)

- **Type:** bug (parser / symtab / static-link — correctness) — Track A
- **Status:** backlog — **symptom 1 fixed** (pin v133, 2026-07-01); symptom 2
  (capturing self-recursion arity) still open, see Log
- **Opened:** 2026-06-30 (found in Track B latent-bug sweep, against stable v97)

## Symptom

Two related nested-procedure defects. Both reject valid Pascal at compile time
(no codegen reached).

### 1. Sibling nested procedure is not visible

A nested procedure cannot call another procedure declared in the *same*
enclosing routine. Minimal repro (6 lines, no captures, no recursion):

```pascal
program v7;
procedure outer;
  procedure a; begin writeln('a'); end;
  procedure b; begin a; end;      { <- a is a sibling of b }
begin b; end;
begin outer; end.
```

```
pascal26:4: error: undefined variable (a)
```

The sibling's name is not in scope inside another nested routine's body.
Declaration order does not help (`a` is declared before `b`). Works fine when
the call comes from the **enclosing** routine's own body — only sibling-to-sibling
fails.

### 2. Capturing nested procedure can't self-recurse

A nested procedure that **captures an outer variable** and **recurses** is
rejected with an arity error:

```pascal
program m1;
function outer(n: integer): integer;
  var acc: integer;
  procedure inner(k: integer);
  begin
    if k>0 then begin acc := acc + k; inner(k-1); end;   { self-call }
  end;
begin acc := 0; inner(n); outer := acc; end;
begin writeln(outer(5)); end.
```

```
Candidate idx 43: paramCount = 2
  param[0] = 1
  param[1] = 1
pascal26:6: error: no overload of inner$18 matches these arguments ()
```

The candidate has `paramCount = 2` (the user param + the hidden static-link /
captured-frame arg), but the self-call site is resolved as passing `()` — the
hidden arg is not supplied, so overload resolution fails.

## Isolation matrix (all against stable v97)

| Case | capture | call from | result |
| --- | --- | --- | --- |
| self-recursion | no | self | **OK** |
| self-recursion | yes | self | FAIL — arity `()` (symptom 2) |
| sibling call | no | sibling nested proc | FAIL — `undefined variable` (symptom 1) |
| sibling call | yes | sibling nested proc | FAIL — `undefined variable` (symptom 1) |
| capturing proc | yes | enclosing routine body | **OK** |

So: the enclosing scope sees its nested procs and passes the static link fine;
a **nested proc body** does not see its sibling procs at all, and even its own
name resolves without the hidden captured-frame argument.

## Likely cause

When building the symbol scope for a nested procedure's body, the parent
routine's *other* nested procedures are not inserted into the visible scope
(only parent vars/params + the proc itself). And the self-name that *is* visible
is the bare user signature, missing the synthesized static-link parameter that
codegen adds for captures — so a same-level call resolves to the wrong arity.
Look at how nested-proc symbols are registered in `symtab.inc` / scope push in
`parser.inc`, and where the hidden static-link arg is appended to the signature
vs. to call sites.

## Acceptance

- `v7` above compiles and prints `a`.
- `m1` above compiles and prints `15`.
- Sibling calls work regardless of declaration order and regardless of capture.
- A capturing nested proc can recurse (direct and mutual).
- Self-host stays byte-identical; add a regression test
  (`test/test_nested_proc_sibling_call.pas`).

## Log
- 2026-07-01 — Symptom 1 fixed, pin v133. Root cause matched the "Likely
  cause" guess exactly: `ParseNestedRoutine`'s call-site rewrite (rename to
  mangled name + splice captured actuals) only scanned the enclosing
  routine's own `begin..end`, deliberately skipping not-yet-lifted sibling
  bodies while locating that block. Fix: widened the rewrite loop's lower
  bound from `parentBegin` to `finalCur` (`compiler/parser.inc`) so it also
  covers those sibling bodies, reusing the exact same rename+splice logic.
  Verified against FPC oracle output: plain sibling call, captured-variable
  sibling call, chained sibling call, Self-capturing sibling call inside a
  method. `test/test_nested_proc_sibling_call.pas` added, wired into
  `make test`. Self-host byte-identical (this lifting mechanism isn't
  exercised by the compiler's own source — worth noting for future pickups:
  self-host passing gives zero signal on this feature's correctness).
  Symptom 2 deliberately left open this pass — the fix shape is understood
  (see below) but touches the same function's fragile token-insertion
  ordering in a second, interacting way; separating them keeps each change
  independently revertable.

### Symptom 2 investigation notes (not yet attempted)

The self-rename loop for a routine's own name (`namePos[]`, handles both the
recursive-call case and the function-result-variable-write case) currently
only overwrites `SOffset`/`SLen` in place — a pure relabel, chosen because it
never changes token count. Fixing the arity bug means that when the routine
captures anything (`nact > 0`), a genuine recursive **call** occurrence (not
a `FuncName := ...` result write — distinguish by checking for a following
`tkAssign`) also needs the same extra actuals spliced in (reusing the
existing `core[]`/`coreCount` array already built for external call sites,
since the lifted routine's own by-ref capture params share the captured
var's original name, so re-passing e.g. `acc` from inside a recursive call
correctly forwards the same reference).

The complication: splicing turns the self-rename into an *insertion*, and
`namePos[]` positions were captured in the same original free-variable scan
pass as `fieldPos[]` (the Self-capture field-prefix insertions, which also
insert tokens and already run earlier in the function). Since both arrays
hold original (pre-edit) token positions, `namePos[]` entries need
compensating for however many `fieldPos[]` insertions land before them
(+2 tokens per such insertion, since positions are disjoint categories and
insertions preserve relative order — the total shift for a stationary point
is exactly `2 * count(fieldPos[j] < namePos[k])`, independent of processing
order). Then splice in descending corrected-position order (same pattern
`fieldPos[]`'s own loop already uses) so each insertion doesn't invalidate
not-yet-processed lower positions.

Worked through this on paper and it looks tractable and contained to
`ParseNestedRoutine`, but there is **no existing regression test for the
lambda-lift/capture feature at all** (confirmed by grepping `Makefile` and
`test/*.pas` — `test_nested_proc_sibling_call.pas` added this session is the
first), and the compiler's own self-host source contains zero nested
routines (confirmed by grep), so self-host byte-identical gives no signal on
correctness here — any mistake in the position-adjustment arithmetic would
only be caught by hand-written test cases, not by the usual gates. Parking
so this can get a clear head and thorough FPC-oracle-diffed testing rather
than being rushed at the tail end of an overnight session.
