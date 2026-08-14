---
track: N
prio: 55
type: bug
summary: "`exec(s, d, d)` compiles, runs, and does NOTHING — the target dict is left empty where CPython has the bound name. A program using it runs and is silently wrong. `eval(s)` is absent entirely (loud, so much less dangerous). Both should map onto the already-shipped feature-lib-pyexec, which does the real work today."
---

# `exec()` builtin is a silent no-op; `eval()` is missing

- **Type:** bug (silent wrong behaviour) — **Track N**.
  Measured by Track T on 2026-08-14 while closing
  [[decide-nilpy-eval-at-runtime]] with the user.

## Measured

```python
d = {}
exec("x = 1 + 2", d, d)
print(sorted(d.keys()))
```

| | pxx | CPython |
| --- | --- | --- |
| the above | **`[]`** | `['__builtins__', 'x']` |
| `eval("1+2")` | `error: undefined variable (eval)` | `3` |
| `exec("x = 1")` then `print(x)` | compile error | `1` |

## The no-op is the dangerous half

`eval` being absent is a **compile error** — loud, immediate, and it names
itself. `exec` is worse: it accepts the call, returns, and binds nothing, so a
program that relies on it runs to completion producing wrong results. That is
the failure mode this repo has paid the most for, and it is exactly what the
NilPy upward-compatibility rule exists to prevent — *code that works on CPython
must work on NilPy*.

## The existing test cannot catch it

`test/test_nilpy_exec_stub.npy`:

```python
d = {}
d["k"] = 5
exec("x = 1", d, d)
print(d["k"])        # <- asserts the PRE-EXISTING key, never "x"
```

It checks that `exec` does not crash and that it does not clobber the dict. It
never checks that `exec` did anything. So the suite is green on a no-op, and has
been.

## The capability already exists — this is wiring, not building

[[feature-lib-pyexec]] is **done**: exec-as-a-library in CPython's explicit-dict
form, no ambient scope capture, host-supplied name -> value bindings including
bound methods of compiled classes (it is how uforth's PYTHON blocks call into
their VM), diffed against `python3`. `compiler/builtin/pyeval.pas` is 5289
lines and there is a compile-time evaluator besides.

So the fix is to route the builtin names onto that, not to write an interpreter.
The user's standing policy, recorded on the decide ticket: where a construct
cannot be settled at compile time, falling back to the runtime library is
legitimate — slower than compiled, correct, with full run-time type information.

Scope worth deciding while implementing rather than after: the library form is
**explicit-dict only**. Ambient-scope `exec("x = 1")` that writes into the
caller's locals is a different and much harder thing in a compiled dialect, and
may belong in `nilpy-semantics-divergences.md` rather than in the fix.

## Gate

The three rows above match CPython. And `test_nilpy_exec_stub.npy` is rewritten
to assert the key `exec` was supposed to define — as written it would pass
against a no-op, which is how this survived.

## Settled 2026-08-14 (user): they are BUILTINS, auto-included — do not ask again

> *"In Python we don't really have some runtime library in that sense. Everything
> is already part of the Python RTL — it's sort of auto-included in every Python
> application as soon as we need it."*

So there is no "expose it as a builtin, or require an import?" question to
resolve while implementing. `eval` and `exec` are **language builtins**, pulled
in on demand like the rest of the NilPy RTL, exactly as CPython presents them.
A program must not have to import anything to use them.

That also settles the naming: the user-visible names are `eval` and `exec`. The
`pyexec` library stays the mechanism underneath; it is not the interface.
