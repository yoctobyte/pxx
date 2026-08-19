---
track: N
prio: 45
type: bug
summary: "`.to_bytes()` on a VARIANT receiver failed at COMPILE time with 'no class declares a method or callable field .to_bytes()' — the intrinsic was gated on a statically int receiver. It is what stopped the uforth corpus compiling at all."
commit: e0c18f95a
---

# `.to_bytes()` on a variant receiver does not compile

Found 2026-08-07 while clearing the uforth blocker that made
[[bug-nilpy-pyeval-fallback-still-binds-host-kwargs-by-position]]'s gate
unreadable ("uforth still green" could not be evaluated because uforth did not
compile).

```python
def f(v):                                    # untyped parameter -> variant
    return v.to_bytes(8, "little", signed=True)
print(len(f(300)))
```

```
pascal26: error: Nil Python: no class declares a method or callable field .to_bytes()
```

CPython prints 8. The message reads as a missing user class rather than a
missing intrinsic, which is what made it hard to place.

## Root cause

`.to_bytes(` is an intrinsic, and both of its hook sites (`parser.inc:5569` in
the lvalue suffix path and `:14407` in ParseFactor's) gated on
`PyIsIntBaseTk(tk)` — a STATICALLY int receiver. A variant one failed the gate,
fell through to the closed-world method dispatcher, which searches user classes
by name, found none, and errored.

A variant int receiver is the ordinary shape: an untyped parameter, a container
element, or `int(x)` where x is dynamic. uforth's is
`int(value).to_bytes(8, "little", signed=True)` inside a property setter —
**line 411, the first thing that stopped that corpus compiling.**

## Fix

`PyIsToBytesBaseTk` replaces the gate at both sites: a static int as before, or
a variant **that no user class could own**. `PyParseToBytes` unboxes a variant
receiver with `pyvar_to_int` before handing it to `pyint_to_bytes(v: Int64; …)`.

The guard is `PyAnyClassDeclares('to_bytes')` — if any user class declares that
name as a method or procedural field, the intrinsic declines and the
closed-world dispatcher keeps it. Without that, the intrinsic would silently
shadow a real method on a variant receiver.

## Measured, controlled against PINNED

| shape | pinned | fixed | CPython |
| --- | --- | --- | --- |
| `v.to_bytes(…)`, v an untyped param | **compile error** | 8, 44 1 … | same |
| `int(v).to_bytes(…)`, v dynamic | **compile error** | correct | same |
| `vals[1].to_bytes(…)` (container elem) | **compile error** | correct | same |
| `n.to_bytes(…)`, n a static int | ok | ok | same |
| `(10).to_bytes(…)` | ok | ok | same |
| user class declares `to_bytes`, variant recv | `packet:7` | `packet:7` | same |
| BOTH in one program, int variant recv | AttributeError | AttributeError | (8) |

The last two rows are **identical before and after** — the guard changes
nothing that already worked, so this is strictly additive.

The last row is a known consequence, unchanged by this fix: the guard is
whole-PROGRAM, so a file that declares its own `to_bytes` keeps the old
behaviour for variant int receivers too (a loud runtime AttributeError, not a
wrong value). Getting that right needs per-receiver runtime dispatch, the same
missing capability as the other variant-receiver rows.

## uforth

Now compiles past line 411 and stops at a different, later gap (line 3352,
`expected newline after statement`) — so this cleared one blocker, not the
corpus. Filed separately if anyone continues.

## Tests

- `test/test_nilpy_to_bytes.npy` extended with the variant rows — 20 lines
  byte-identical to the CPython oracle.
- `test/test_nilpy_to_bytes_user_class_wins.npy` pins the guard, so the
  intrinsic cannot be widened later without noticing — 3 lines, oracle-diffed.

## Gate

`make fpc-check` byte-identical, self-host fixedpoint, `tools/gate.sh quick`
GREEN.
