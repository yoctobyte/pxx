---
track: N
prio: 60
type: bug
status: working
owner: claude-AN
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


## 2026-08-04 (claude-AN) — option 1 IMPLEMENTED and MEASURED; the field half landed, the rest is parked on cost

Picked this up with the Track U decision already resolved (option 1), built it,
and measured it. Everything below is measured against a self-hosted binary at
HEAD, not reasoned.

### Landed: the FIELD half of the 2026-07-31 addendum

The 2^31 field cliff was not the promotion design at all — it was
`PyTypeFromTokenIndex` disagreeing with itself. An `int` **annotation** mapped
to `tyInt64`; an integer **literal** mapped to `tyInteger`, 4 bytes. So
`self.v: int = 0` gave an 8-byte field and `self.v = 0` gave a 4-byte one, and
the addendum's whole table — 2^31 coming back `-2147483648`, everything from
2^32 up coming back `0`, through every host-bridge route — followed from that
one line. Fixed; the addendum's ladder now matches CPython through 2^62, and
`test/test_nilpy_int_field_width.npy` pins both spellings so they cannot drift
apart again. Beyond 2^63 a field still wraps, which is this ticket's headline
case, below.

### Built, gated GREEN, and NOT landed: option 1 itself

Two changes, preserved as patches under `devdocs/progress/patches/`:

- `int-promotion-option1-arith-typing.patch` — `PyIntGrowsOp` /
  `PyIsMachineIntTk` in `symtab.inc` plus an arm at each of the two binop
  typing sites in `parser.inc`, PyExprMode-gated, typing `+ - *` over two
  native ints as `tyPromoInt64`. Only the operators that can GROW a value;
  `//`, `%`, the bitwise ops and the comparisons keep native codegen and cost
  nothing. `<<` already did this at its own site.
- `int-promotion-option1-module-scope.patch` — module scope needed two more
  things, because its pre-pass may not trial-parse inside a block: recognising
  `for i in range(...)` as an int induction variable, and recognising
  `n = n * 2` as int arithmetic from tokens alone.

With both applied, every row of this ticket's table matches CPython:
`n = 1` grown 70 times, `9223372036854775807 + 1`, `-9223372036854775807 - 10`,
and factorial(25) accumulated in a loop. `tools/gate.sh quick` GREEN,
self-host byte-identical.

### Three regressions it exposes, all narrow

Surveyed 17 builtins and container operations with a promo argument. Exactly
three broke — `hex`, `bin`, `oct`, which are plain `Int64` Pascal routines in
`pylib.pas` and need a `PromoInt` overload each. `str`, `abs`, `float`, `chr`,
`divmod`, `max`, `min`, `round`, `pow`, indexing, slicing, `*` repeat and
`for i in range(...)` all already handle a promo operand. (`print(range(x))` and
`list(range(x))` also fail, but they fail identically on `pinned` — that is
[[bug-nilpy-missing-builtins-step-slicing-range-into-list]], not this.)

### Why it is parked: it costs 10x, and this ticket's own gate forbids that

The gate on this ticket asks for "a benchmark check that ordinary integer loops
have not regressed". They regress by **10.1x** — a 20M-iteration
accumulate-and-count loop goes 0.868 s → 8.739 s, which also flips NilPy from
1.35x faster than CPython on integer code to 7.4x slower. Every promo operation
is a runtime call today (`feature-a-promoint-check-elision`), so the cost is one
call per operator.

The implementation is not what is wrong. Both the accumulator and the counter
are genuinely unprovable — `i = i + 1` bounded by `i < n` says nothing about
`n` — so the "native where the frontend can prove the range" half of option 1
needs a real range analysis that does not exist yet.

That is a cost the decision was taken without, so it goes back to the user
rather than being absorbed: **[[decide-nilpy-int-promotion-costs-10x-on-ordinary-loops]]**,
recommending that `feature-a-promoint-check-elision` be funded first. Moving to
`unfinished/` — the patches apply cleanly and the next session's work is
whichever branch of that decision is taken, plus the three overloads.


## 2026-08-04 (later) — the cost decision is MADE, but landing is blocked on a surface my earlier survey missed

Rene decided the 10x is acceptable ("python wasn't meant for performant tight
loops in the first place"), so `decide-nilpy-int-promotion-costs-10x-on-ordinary-loops`
is settled in favour of option 1. The patches were re-applied to land it. **They
do not land**, and the reason is a mistake in this ticket's own earlier findings.

### My "blast radius is three builtins" was measured WRONG

The 2026-08-04 survey said only `hex`, `bin` and `oct` broke out of seventeen
builtins probed. That survey checked **whether the program COMPILED**, not what
it printed. Re-run comparing OUTPUT against CPython, with the patches applied:

| shape | with option 1 |
| --- | --- |
| `hex/bin/oct(promo)` | fixed separately (`762c7addf`) |
| `str(i + 1)` | printed **5553064** — the slot address |
| `round(i + 1)` | printed **5553112** — the slot address |
| `"ab" * (i + 1)` | printed **empty** |
| `[0] * (i + 1)` | raised `TypeError: unsupported operand type(s)` |

`[0] * n` is how Python allocates a fixed-size list and appears in the existing
test corpus, so this is not an edge case — it is a core idiom, and it is the one
that makes landing impossible today.

### Each is the same shape, and there are probably more

A promotable int reaching a **hand-built call site or a static-type predicate
that does not know about promo**. Promo is deliberately not reported by
`TypeIsOrdinal` / `TypeIsPyNumeric`, and `FindProc` never consults overloads, so
every such site needs its own arm:

- `str`'s intrinsic hand-builds `pystr_of` via `FindProc` → **fixed and landed**
  (it is reachable today with a wide literal: `str(1180591620717411303424)`
  printed an empty line on `pinned`).
- `pystr_repeat`'s count was lowered with a raw `IRLowerAST` and a promo count
  was diverted into the float arm → **fixed and landed**.
- `round`'s intrinsic — same `FindProc` shape, NOT fixed.
- The list-repeat path goes through `IRPyStaticPairUndefined`, which classifies a
  promo operand as kind 0 (unknown) and calls the pair provably-undefined.
  Adding promo to `IRPyOperandKind` was tried and **made it worse** — the
  TypeError became a garbage number — so that predicate is not the only thing
  in the way. Reverted.

The honest conclusion: **the promo surface has not been enumerated.** What is
needed before this can land is a sweep that runs a large probe corpus with the
patches applied and DIFFS THE OUTPUT, not a spot-check of a handful of builtins,
and then an arm per site. That is a piece of work in its own right and should be
a ticket, not a footnote here.

### What landed anyway

The two fixes above stand on their own — both are reachable today via a wide
literal, both verified against CPython, both wrong on `pinned`. Refreshed
patches for the promotion typing itself are in
`devdocs/progress/patches/` and still apply.

Remains `unfinished/`, no longer blocked on the decision — blocked on the surface
sweep.
