# Typed-constant `array of string` is broken (segfault ≤2 elems, bogus error ≥3)

- **Type:** bug (consteval / data emission — correctness) — Track A
- **Status:** backlog
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

## Acceptance

- `const A: array[0..2] of string = ('a','b','c'); writeln(A[0],A[1],A[2])`
  prints `abc`; 1- and 2-element string const arrays run without segfault.
- Larger string const arrays compile up to the real capacity limit.
- Regression test (`test/test_const_array_of_string.pas`) wired into `make test`;
  self-host stays byte-identical.
