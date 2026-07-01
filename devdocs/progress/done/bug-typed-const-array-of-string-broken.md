# Typed-constant `array of string` is broken (segfault ≤2 elems, bogus error ≥3)

- **Type:** bug (consteval / data emission — correctness) — Track A
- **Status:** done — duplicate of [[bug-const-array-of-ansistring-literal-too-many-elements]],
  which fixed this exact symptom at v115 (2026-07-01). Re-verified 2026-07-01:
  all three repros in this ticket (1/2/3-element `array of string`) now
  compile and run correctly (`test/test_const_array_of_string.pas`, already
  wired into `make test`). Closing without further changes.
- **Severity:** medium-high — `const Names: array[..] of string = (...)` is a
  very common idiom (month/day names, enum labels, error tables); it is
  completely unusable today.
- **Opened:** 2026-06-30 (Track B latent-bug sweep, against stable v97)

## Symptom

A typed constant array whose element type is `string` either silently produces
broken data (runtime segfault on first access) or is rejected with a misleading
capacity error, depending on element count:

```pascal
const A: array[0..0] of string = ('a');            { compiles, SEGFAULT reading A[0] }
const A: array[0..1] of string = ('a','b');        { compiles, SEGFAULT reading A[0] }
const A: array[0..2] of string = ('a','b','c');    { error: too many array constant elements }
```

The same shapes with non-managed element types work fine:

```pascal
const P: array[0..4] of integer = (2,3,5,7,11);    { OK }
const C: array[0..2] of char    = ('a','b','c');   { OK -> abc }
```

So the trigger is the **string (managed) element type**, not the element count
or the index base (0-based and 1-based both fail identically).

## Isolation (stable v97)

| Declaration | Compiles? | Runs? |
| --- | --- | --- |
| `array[0..4] of integer = (...)` | yes | OK |
| `array[0..2] of char = (...)` | yes | OK |
| `array[0..0] of string = ('a')` | yes | **SIGSEGV** |
| `array[0..1] of string = ('a','b')` | yes | **SIGSEGV** |
| `array[0..2] of string = ('a','b','c')` | **no** — `too many array constant elements` | — |

Two distinct failure modes from one root: the const-array element emitter
doesn't handle managed-string elements (emits no/garbage string handle → deref
segfaults), and the element *counter* appears to overcount string entries (3
literals trip the `MAX_*` element ceiling, hence the bogus "too many" at 3 — note
this is a *different* defect from the genuine capacity wall in
[[bug-array-const-too-many-elements-synapse]], which needs many elements).

## Likely cause

The typed-const array path emits element data assuming a fixed scalar element
size and a plain literal value. A `string` element needs a managed-string
constant (a pointer to const string data + length, ARC-aware), which the const
emitter does not build — so the slot holds garbage and the overrun also confuses
the element-count check. Look at where typed-const array initializers are
lowered (consteval / static data emission) and add a managed-string element case
mirroring how a single `const s: string = '...'` is emitted.

## Additional isolation (2026-06-30, found independently while building lib/asmcore)

Hit the same `too many array constant elements ()` message via a different
trigger axis: **element string length**, not just element count. Minimal
repro, a single-element array:

```pascal
const a: array[0..0] of AnsiString = ('r0');   { error: too many array constant elements () }
const a: array[0..0] of AnsiString = ('ab');   { same error }
const a: array[0..0] of AnsiString = ('0');    { compiles (didn't verify runtime correctness) }
const a: array[0..0] of AnsiString = ('r');    { compiles (didn't verify runtime correctness) }
```

So with a **1-element** array (which this ticket's table shows segfaults
rather than erroring, for 1-char elements `'a'`), a **2+ character** string
literal flips it straight to the "too many" error instead of compiling-then-
segfaulting. Consistent with this ticket's existing hypothesis ("the element
counter appears to overcount string entries") — looks like whatever counts
elements is counting something proportional to *string content* (characters,
bytes, or similar) rather than array elements, so both element count *and*
per-element string length shift when the bogus ceiling trips. Real-world
trigger: `array[0..15] of AnsiString` register-name tables (`'rax'`, `'r10'`,
etc., 2-3 chars each) — exactly the multi-char-string-array idiom this
ticket already flags as "very common."

## Acceptance

- `const A: array[0..2] of string = ('a','b','c'); writeln(A[0],A[1],A[2])`
  prints `abc`; 1- and 2-element string const arrays run without segfault.
- Larger string const arrays compile up to the real capacity limit.
- Regression test (`test/test_const_array_of_string.pas`) wired into `make test`;
  self-host stays byte-identical.
