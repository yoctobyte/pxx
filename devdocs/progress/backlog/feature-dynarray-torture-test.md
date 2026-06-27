# Dynamic-array torture test — make dynarray trustable

- **Type:** feature (test / compiler-correctness) — Track A
- **Status:** backlog
- **Owner:** unassigned
- **Opened:** 2026-06-27
- **Relation:** the standalone confidence-builder for
  [[feature-dynamic-compiler-tables]] (which would self-host the compiler on
  dynarrays — only worth doing once dynarray is trusted). Touches
  [[design-record-copy-dynarray-field-semantics]] (deep-copy vs FPC's shared
  reference).

## Goal

One (or a few) deliberately nasty Pascal program(s) that exercise dynamic arrays
in the weirdest combinations we can think of, with a deterministic oracle
(expected stdout / exit code). **It does not have to pass.** The point is to find
where dynarray support is wrong or missing. Every failure → a new specific
bug/feature ticket. Run it against `$(PXX_STABLE)` and across targets.

## What "weirdest stuff" should cover

- **Grow / shrink:** repeated `SetLength` up and down; verify contents preserved
  on grow, truncated on shrink, new slots zeroed.
- **Jagged / N-D:** dynarray of dynarray (ragged rows); `SetLength(a, x, y)`
  multidim; element-of-row as lvalue.
- **Managed elements:** dynarray of `string`; dynarray of record with a managed
  (string / dynarray) field; nested dynarray-of-record-of-dynarray-of-string.
- **Copy vs reference semantics:** `b := a` then mutate `b` — does `a` change?
  (PXX deep-copies, FPC shares; pin the chosen semantics with an oracle and a
  note.) Same for a dynarray *field* on record copy.
- **Aliasing / lifetime:** alias, free one, read the other; nil/empty array
  (`Length(nil)=0`, iterate empty); reassign to shorter/longer.
- **Intrinsics:** `Length` / `High` / `Low`; `Copy(arr, i, n)`; `Insert` /
  `Delete` (string siblings done; **dynarray** Insert/Delete known-incomplete);
  `Concat` / `a + b` if supported; `SetLength` on a function-result array.
- **Passing / returning:** dynarray as value / `var` / `const` param; returned
  from a function; element passed as a `var`/`out` actual; open-array coercion.
- **In aggregates:** dynarray as a class field (`SetLength(Self.F, n)`); record
  with dynarray field copied by value; array-of-record where the record holds a
  dynarray.
- **Stress:** large arrays forcing heap realloc; many grow/shrink cycles to flush
  double-free / leak / use-after-realloc bugs.
- **for-in** over a dynarray (value + element mutation rules).

## Method

- Each scenario prints a small deterministic marker; the program's full stdout is
  the oracle. Where PXX semantics intentionally differ from FPC (deep copy),
  record the chosen behaviour as the oracle, not FPC's.
- Build with `$(PXX_STABLE)`; also run under the cross harness
  (i386/arm32/aarch64/riscv32) — managed-dynarray ABI bugs surface cross-target,
  not on x86-64.
- Expect failures. For each, file a focused ticket (link back here) rather than
  patching inline.

## Acceptance

- A `test/test_dynarray_torture.pas` (and/or a few split files) committed and
  wired into the suite (even if marked allow-fail initially).
- A first run logged here, with one ticket filed per distinct failure.
- Over time: all scenarios green on x86-64 + cross ⇒ dynarray is trusted ⇒
  unblocks the [[feature-dynamic-compiler-tables]] dogfood.

## Log

- 2026-06-27 - Filed (user). Build a dynarray torture app; goal = trust, not a
  green run; expected to spawn new tickets.
