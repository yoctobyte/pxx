---
track: A
prio: 45
type: task
---

# Carve NilPy's selector/subscript parsing out of `parser.inc`

**User, 2026-08-09:** *"parser support functions — instead of being a solution
for multiple languages, as soon as those languages diverge, there is no shame in
copying the helper function and make it language specific."*

This extends the standing rule (`feedback_duplicate_helpers_per_language_shared_ast`,
2026-07-20) from RUNTIME helpers to PARSE routines. The shared thing is the
AST/IR — not the parser.

## Measured

| | count |
| --- | --- |
| `PyExprMode` guards in `compiler/parser.inc` | **129** |
| `isNilPy` guards in `compiler/parser.inc` | 67 |
| `PyExprMode` guards in `ParseClassRecordSelectors` **alone** | **34** |

A function with 34 dialect tests is two functions interleaved.

## Why it is not cosmetic — two bugs from one day

- **`f()[1]` on a string-returning call returned character 0.** The shared
  `tyAnsiString + tkLBrack` arm applied **Pascal's 1-based index** to a NilPy
  expression. The defect was not a MISSING NilPy arm; it was the Pascal arm
  quietly serving NilPy. `f()[0]` was "correct", so it survived a long time.
- **A `@dataclass`'s `str` default silently became `''`.** A defensive
  "fill every unsupplied string parameter" loop ran ahead of the dataclass
  defaults and consumed the slot.

Both share a shape: **the wrong dialect's behaviour is the DEFAULT, and the
right one is an arm someone has to remember to add.** A split inverts that — a
NilPy-only routine cannot accidentally do the Pascal thing, because the Pascal
code is not in it.

## Scope

Start with `ParseClassRecordSelectors` — the densest, and the one that produced
both bugs. Copy it into `pyparser.inc` as a NilPy-only selector parser, delete
the Pascal arms from the copy and the NilPy arms from the original, and call the
copy from the NilPy entry points. NilPy already owns `pylexer.inc` /
`pyparser.inc`; selector parsing living in `parser.inc` is the anomaly.

Do NOT attempt all 129 at once. One routine per change, each landing green, with
the guard count recorded so the trend is visible. Some guards are genuinely
about *shared* behaviour (a NilPy-only diagnostic on a shared construct) and
should stay — the test is whether the two dialects want different SEMANTICS
there, not merely different messages.

## Note on the Pascal side

`parser.inc` is Pascal's frontend as well as the shared expression parser, so
this is Track A ground and carries the self-host gate. The self-host fixedpoint
is a strong oracle for the Pascal half: if the carve-out changes Pascal
behaviour at all, the compiler stops reproducing itself. Use that — it makes the
Pascal side of each split nearly free to verify, which is the opposite of the
NilPy side.

## Gate

Per routine: `make compiler/pascal26` (the fixedpoint) + `tools/gate.sh quick`,
plus a whole-suite HEAD-vs-pinned `.npy` sweep — a carve-out is a NARROWING
change, and narrowing cannot be regression-tested by the tests that motivated
it (that is how the exact-case ctor fix broke aliased constructors the same day
and was caught only by the sweep).
