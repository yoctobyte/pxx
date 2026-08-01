---
track: N
prio: 60
type: bug
---

# Promotion is chosen from the LITERAL's width, so an int that grows past 2^63 wraps silently

```python
n = 1
for i in [0] * 70:
    n = n * 2
print(n)          # CPython: 1180591620717411303424     pxx: 0

n = 9223372036854775807
print(n + 1)      # CPython: 9223372036854775808        pxx: -9223372036854775808
```

Python's `int` is arbitrary precision, and [[feature-a-promotable-int]] built
exactly that (fixnum → heap bignum). It works — but only when the STATIC type
came out promotable, and that is decided by how wide the initialising literal
was.

## Measured — the boundary is the initialiser, not the arithmetic

| case | CPython | pxx |
| --- | --- | --- |
| `n = 123456789012345678901234567890; n` | correct | correct |
| `n = <big literal>; n + 1` | correct | correct |
| `n = <big literal>; n * 2` | correct | correct |
| `a, b = <two big literals>; a - b` | `1` | `1` |
| `n = <big literal>` then `n = n + n` in a loop | correct | correct |
| **`n = 1`** then `n = n * 2` seventy times | `1180591620717411303424` | **`0`** |
| **`n = 9223372036854775807`; `n + 1`** | `9223372036854775808` | **`-9223372036854775808`** |
| **`n = -9223372036854775807`; `n - 10`** | `-9223372036854775817` | **`9223372036854775799`** |
| **factorial(25) accumulated in a loop** | `15511210043330985984000000` | **prints nothing** |

So a value that STARTS big stays correct all the way, and a value that starts
small and grows wraps at 2^63 with no diagnostic. Which is the wrong way round:
the literal that overflows is the case a programmer notices, and the
accumulator is the case they do not.

The factorial row is worth a second look on its own — it produces no output at
all rather than a wrong number, which suggests something beyond a silent wrap.

## Why this is not simply "the feature is unfinished"

[[feature-a-promotable-int]] deliberately keeps loop induction variables,
indices and `len()` results as native int64 "with no checks at all" — that is a
sound performance decision and should stay. The gap is that a general-purpose
binding gets the same treatment purely because its first assigned literal fit in
a word. An accumulator is not an induction variable, and nothing distinguishes
them today.

## Options — probably wants a Track U call

1. **Default NilPy `int` bindings to promotable**, and keep native int64 only
   where the frontend can prove the range (an induction variable of a `range`
   loop, a `len()` result, an index). Correct by default, pays where it must;
   the cost lands on ordinary integer code, which is most code.
2. **Promote on overflow at run time** — keep the native representation and
   escalate the binding when an operation carries out. Needs an overflow check
   on every arithmetic op that could, and a way to re-type a live binding.
3. **Widen only when a binding is ASSIGNED FROM a promotable expression**, i.e.
   propagate promotability through the assignment graph rather than from the
   initialiser alone. Cheaper than 1, catches the accumulator, still misses
   `n = 1` growing purely by native arithmetic.

Recommendation: 1, with the proof-based exceptions the feature ticket already
names — it is the only one that makes `int` mean what Python says it means. But
it is a performance-relevant default, so file the decision rather than picking
it here.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` of the table above
against CPython's own output, and a benchmark check that ordinary integer loops
have not regressed (that is the whole cost of option 1).

## 2026-07-31 (Track B) — a FIELD is much narrower than 2^63: it wraps at 2^31

Found gating [[feature-lib-pyexec]]'s `exec()` surface from a `.npy`. The table
above measures locals wrapping at 2^63; a FIELD whose initialiser is a small
literal wraps at **2^31**, signed:

```python
class B:
    def __init__(self):
        self.v = 0
b = B()
b.v = 4294967296
print(b.v)          # CPython: 4294967296     pxx: 0
```

A ladder pins it exactly — `2^30` is right, `2^31` comes back
**-2147483648** (the sign flip), and every value from `2^32` up comes back
**0**:

| assigned | CPython | pxx |
| --- | --- | --- |
| 2^30 | 1073741824 | 1073741824 |
| 2^31 | 2147483648 | **-2147483648** |
| 2^32 | 4294967296 | **0** |
| 2^40 … 2^62 | correct | **0** |

Same cause as the ticket's — the static type comes from the initialising
literal, and `self.v = 0` makes the field a 32-bit Integer — but two orders of
magnitude sooner than 2^63, and a field is exactly where an accumulator lives.

### It is inherited by everything that crosses the host bridge

The value is fine INSIDE `exec()` — `y = 4294967296; print(y)` prints it
correctly — and truncates on the way out, through every route:

| route | result |
| --- | --- |
| `push(4294967296)` (bound method in env) | 0 |
| `vm.push(4294967296)` (qualified, generalized trampoline) | 0 |
| `vm.w = 4294967296` (field assignment) | 0 |
| `env["big"] = 4294967296` then `push(big)` (value supplied BY the host) | 0 |
| `print(y)` inside the exec'd source | **4294967296, correct** |

That last row is what identifies it: pyeval holds the value correctly, so this
is not an interpreter bug and there is no separate pyeval ticket for it. The
32-bit field is the whole story, and every host-bridge path merely reports it.

## 2026-08-01 (Track N, claude-N2) — parked on the existing Track U decision

Picked this up to fix. Before touching `pyparser.inc`, checked whether the
"probably wants a Track U call" note in this ticket had already been acted on:
it has — `[[decide-nilpy-int-promotion-default]]` exists in
`devdocs/progress/backlog/`, states this exact fork (the three options above,
verbatim), and is **still unresolved** (sitting in `backlog/`, not `decided/`).

Per the project's Track U rule ("escalate, don't guess" — a design/default
call that can't be settled from the code or a sane default gets filed and left
for the user, not picked by the agent), I am not implementing any of the three
options unilaterally:

- Option 1 (default every NilPy `int` to promotable) is a real perf-relevant
  default change across all NilPy integer code — exactly the kind of call the
  decide-ticket says needs a benchmark-backed decision, not an agent's guess.
- Option 3 (propagate promotability through the assignment graph) is
  containable inside `pyparser.inc` (Track N's own files, no Track A ask) and
  would fix the "grows via assignment from a promotable expr" shape, but the
  decide-ticket is explicit that it does **not** close the ticket's headline
  case (`n = 1; n = n * 2` growing via native arithmetic alone) — landing a
  partial fix here risks the ticket reading "fixed" when it isn't, and
  pre-empts whichever option the user actually picks (1 supersedes 3 entirely).
- Option 2 (runtime promote-on-overflow) needs a way to re-type a live binding
  mid-lifetime, which nothing in the current model supports — bigger than a
  Track N-scoped change regardless.

Did NOT touch `compiler/pyparser.inc`, `compiler/pylib.pas`, or any promotable-
int runtime machinery. No code changes in this session. Moved to `blocked/`
pending the Track U decision.

## 2026-08-01 — DECIDED: option 1

[[decide-nilpy-int-promotion-default]] resolved: default every NilPy `int`
binding to promotable, native int64 only where the frontend can prove the
range. Unblocked — moving back to `backlog/` for Track N (or A, if it needs
new symtab/IR machinery). Gate unchanged: `make test-nilpy` + self-host
byte-identical + the ticket's own measured table vs CPython + a benchmark
check that ordinary integer loops haven't regressed.
