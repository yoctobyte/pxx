---
summary: "nilpy: reading a DEFAULTED variant parameter segfaults (by-ref seen as by-value)"
type: bug
track: N
prio: 65
---

# nilpy: omitted `x=None` parameter on an UNANNOTATED def segfaults

- **Type:** bug (Nil-Python frontend) — **Track N**
- **Opened:** 2026-07-27. Pre-existing: reproduces on the PINNED stable, with no
  `*args` forwarding involved (found while landing that).

## Repro

```python
def get(a, b, default=None):
    if default is None:
        return "none"
    return "some"

print(get("x", "y"))          # SEGFAULT
print(get("x", "y", "z"))     # fine
```

Compiles clean, crashes at run time. Passing the third argument explicitly works,
so it is the OMITTED default that is wrong, not the body.

## What it actually is — the measured matrix (2026-07-27)

The first reading ("the omitted default is filled with a raw 0") is WRONG. The
trigger is a DEFAULTED variant parameter being READ, whatever the argument was:

| signature | call | body reads d | result |
| --- | --- | --- | --- |
| `g(a, d)` | `g("x", None)` | `str(d)` | prints `0` (wrong value, no crash) |
| `g(d)` | `g(None)` | `str(d)` | prints `0` |
| `g(a, d=None)` | `g("x", None)` | `str(d)` | **SEGFAULT** |
| `g(a, d=0)` | `g("x", None)` | `str(d)` | **SEGFAULT** |
| `g(a, d=None)` | `g("x")` | `str(d)` | **SEGFAULT** |
| `g(a, d=None)` | `g("x", 5)` | `d is None` | fine |
| `g(a, d=None)` | `g("x", None)` | body ignores d | fine |
| `g(a, d=None)` | `g("x", 5)` | `str(d)` | **SEGFAULT** |

The last row is the decisive one: a perfectly ordinary argument, and it still
crashes. So it is not the fill value and not None: it is the DECLARED DEFAULT. `is None`
(which only reads the tag) survives where `str(d)` (which dereferences the
payload) crashes, which points at the callee seeing the parameter at the wrong
place — a by-value/by-reference disagreement for a variant parameter that
carries a default, rather than a bad argument.

Two fixes were tried and REVERTED because neither addressed it: filling the
omitted default with `pynone()` in DefaultArgValueNode, and passing the address
of a zeroed variant local from the IR-side default fill (ir.inc). Both are
plausible in isolation; the crash survives both, so the disagreement is on the
CALLEE side. Start there: compare what AllocParam/Procs[].IsRef and
ProcParamIsConst say for a defaulted variant parameter against an undefaulted one.

## Original reading (kept for the record)

## Why it is likely happening

An unannotated parameter is typed Any, i.e. `tyVariant`, and a variant parameter
is passed by REFERENCE (the callee reads a 16-byte slot through a pointer — see
the note in PyClassCreate about exactly this hazard for constructor defaults,
where `valNode := PyMakeNone` was needed instead of an `AN_INT_LIT 0`). The
ordinary call path's trailing-default fill appears to hand a plain integer 0 for
the omitted argument, so the callee dereferences 0 when it touches the parameter.
`PyClassCreate` already carries the fix for the ctor flavour of this; the def
flavour looks unfixed.

## Why it matters

`def f(..., default=None)` is one of the most common Python signatures there is,
and songformatter's `settings.get(section, option, default=None)` is exactly it.
Any `.npy` calling such a def without the last argument crashes.

## Gate

`make test-nilpy` green with a `.npy` case covering an omitted `=None` parameter
on an unannotated def, tested BOTH ways (omitted and supplied) and diffed against
CPython, + `--tier quick` + self-host byte-identical.

## Log
- 2026-07-28 — resolved, commit 13a8e4213.

## Resolution

Fixed with the rest of the default-argument machinery in 13a8e4213
("fix(nilpy): a declared default is what the callee actually runs with"), which
moved the fill to the callee so an omitted variant default is a real None
rather than a raw ordinal handed across a by-reference parameter. The ticket was
left in `backlog/` by that commit.

Re-verified 2026-07-28: this ticket's repro prints `none` / `some`, matching
CPython, with no segfault.
