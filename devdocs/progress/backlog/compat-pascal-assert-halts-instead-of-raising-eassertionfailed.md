---
track: P
prio: 55
type: bug
summary: "Pascal's Assert() halts with 227 even when sysutils is used, so `try Assert(...) except` cannot run — FPC raises a catchable EAssertionFailed, and our RTL already declares the class but nothing raises it"
---

# `Assert()` halts instead of raising `EAssertionFailed`

- **Type:** bug / FPC-parity divergence — **Track P** (compat tag)
- **Found:** 2026-08-02, prompted by the question "don't we have assert in
  Pascal already?" while adding NilPy's `assert` statement
  ([[bug-nilpy-assert-statement-not-supported]], fixed in `74b8bc37d`).
- **Measured against FPC directly, not reasoned.**

## The divergence

```pascal
{$mode objfpc}{$H+}
program a;
uses sysutils;
begin
  try
    Assert(1 = 2, 'boom');
  except
    on E: Exception do WriteLn('caught: ', E.ClassName, ': ', E.Message);
  end;
  WriteLn('still running');
end.
```

| | output | exit |
| --- | --- | --- |
| **FPC** (`-Sa`) | `caught: EAssertionFailed: boom (a.pas, line 6)` then `still running` | 0 |
| **pxx** | `Assertion failed: boom` | **227** |

`__pxxAssert` (compiler/builtin/builtin.pas) does `writeln` + `Halt(227)`
unconditionally. So the handler never runs and everything after the `try` is
lost.

## Why this is the interesting kind of bug

It is the **same failure family** as three NilPy bugs fixed the same night: a
diagnostic path that ABORTS the process where the reference implementation
RAISES, so a `try/except` around it cannot run its handler. It was invisible
here because the abort *looks* like correct behaviour — the message is right and
the exit code is even FPC's own 227.

The 227 is what makes it plausible: that IS what FPC does — but only when
SysUtils is NOT used. With SysUtils, FPC's behaviour changes.

## Cause, and why the fix is already half-present

FPC's mechanism is a hook: `System.AssertErrorProc` is a procedure variable that
defaults to "print and run-error 227", and **SysUtils installs its own** which
raises `EAssertionFailed`. That is the entire difference.

We already have the destination:
`lib/rtl/sysutils.pas:107` declares `EAssertionFailed = class(Exception) end;`
— but nothing raises it, and there is no `AssertErrorProc` anywhere in the tree.

So the fix is to reproduce FPC's shape rather than invent one:

1. add an `AssertErrorProc`-style hook beside `__pxxAssert` in builtin
2. `__pxxAssert` calls the hook when set, else keeps today's print + Halt(227)
3. `sysutils` sets it at unit init to raise `EAssertionFailed` with the message

That keeps a no-sysutils program byte-identical to today (which is also correct
FPC behaviour) and fixes only the case that currently diverges.

## Second, smaller divergence found at the same time

FPC compiles assertions **out** unless `-Sa` / `{$ASSERTIONS ON}`; pxx always
evaluates them. That is the lax direction (we run a check FPC skipped) and does
not produce a wrong value, so it is noted rather than filed separately — but if
`{$ASSERTIONS}` is ever implemented, these two want doing together.

## Gate — note the pin

`__pxxAssert` lives in `compiler/builtin/`, so this change makes `gate.sh`'s
self-host fixedpoint report A != B until `make stabilize` + `make pin`
([[project_builtin_change_needs_repin_for_gate_fixedpoint]]). That is not a
regression, it is the frozen-builtin boundary — budget for the repin.

Test: the program above, plus the no-sysutils case still halting with 227, plus
`Assert` with no message, plus a passing assertion.
