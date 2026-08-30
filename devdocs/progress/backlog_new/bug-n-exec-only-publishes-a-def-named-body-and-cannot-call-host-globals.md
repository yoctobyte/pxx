---
track: N
prio: 45
type: bug
blocked-by: []
status: new
owner: ""
found: 2026-08-30
found-by: frank-optimize, profiling bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython
summary: "pyeval's exec() publishes exactly one def into the caller's namespace — one literally named __body__, hand-wired at pyeval.pas:5748 to uforth's wrapper idiom. `exec(\"def body(): return 1\", {}, ns); ns[\"body\"]()` raises KeyError under pxx and prints 1 under CPython. Two more refusals in the same family: a function in the globals dict is not callable from the exec'd body, and attribute access on a parameter raises 'no RTTI for attribute'. All three are programs CPython accepts and runs, so all three are N bugs by the upward-compatibility rule."
---

# `exec()` only publishes a def named `__body__`, and cannot call host globals

## Four one-liners, measured at `0604b414089f`

Each is a complete program. `cpython` is 3.14.4.

| # | program | pxx | CPython |
| --- | --- | --- | --- |
| 1 | `ns={}; exec("def body():\n    return 1\n",{},ns); print(ns["body"]())` | `KeyError: 'body'` | `1` |
| 2 | same, but the def is named `__body__` | `1` | `1` |
| 3 | `__body__` body calls `hostfn()` passed in the globals dict | `pyeval: unknown call: hostfn()` | `42` |
| 4 | `exec("def __body__(o):\n    return o.v\n",{},ns); ns["__body__"](C())` | `pyeval: no RTTI for attribute v` | `7` |

Row 1 vs row 2 is the whole ticket in two lines: **the name is load-bearing.**

## Why

`compiler/builtin/pyeval.pas:5731-5754`, and the code says so itself:

```pascal
{ The uforth exec() idiom is `exec("def __body__(): ...", env, ns)` followed by
  `ns["__body__"]()`. [...] Publish it into the caller's namespace as a callable
  variant so the separate `ns["__body__"]()` reaches it }
if (l <> nil) and (FnFind('__body__') >= 0) then
  l.store(MakeStr('__body__'), pyvar_of_callable(Pointer(@PyBodyTramp)));
{ ...and every other top-level binding, which is the general case the
  `__body__` line above was the one hand-wired instance of. }
if l <> nil then
  for si := 0 to LclN - 1 do
    l.store(MakeStr(LclNames[si]), LclVals[si]);
```

The comment calls the second loop "the general case", but it publishes top-level
**bindings** (`LclNames`/`LclVals`), and a `def` is not one — `ExecDef` records a
body span in the function table, not a local. So exactly one def reaches the
caller's namespace, and only because its name is spelled out in the source.

The hazard the surrounding comment documents at length (`pyvar_of_callable` vs
`PyBoxObj`, and the segfault that came of getting it wrong) is real and its fix
is correct. It is the *keying* that is the bug, not the boxing.

## Suggested work

Publish **every** def registered by this `exec` as a callable, keyed by its own
name, instead of the one hard-coded name — i.e. iterate the function table the
same way the second loop iterates bindings, and drop the special case. Row 2
then stops being privileged and row 1 starts working.

Rows 3 and 4 are separate defects in the same call and may want their own
tickets once row 1 is fixed; they are recorded here because they were found in
one sitting and a fix for row 1 should not be claimed as a fix for the family.

- **Row 3** — names in the `globals` mapping passed to `exec` are not resolvable
  as call targets from inside the exec'd body. uforth's own `env` (holding `vm`
  and four bound methods) *does* work, so some entries resolve and some do not;
  the boundary is not yet characterised.
- **Row 4** — attribute access on a parameter of the exec'd function is refused
  for want of RTTI. This is what blocked caching uforth's compiled body, which is
  otherwise a 2.6x win under CPython (1.46s → 0.57s on `coreexttest.fth`).

## Why this is an N bug and not a compat item

CPython accepts and runs all four programs; pxx does not. That is the
upward-compatibility direction, which `CLAUDE.md` makes the definition of an N
bug: *if code works on CPython, it must work on NilPy.* No divergences-doc entry
applies — nothing here is NilPy being laxer than CPython.

## Gate

`test-nilpy` green + self-host byte-identical. The four rows above belong in the
suite as `.npy` tests; row 1 in particular is two lines and would have caught
this the day the hand-wiring landed.

## Note for whoever takes it

`uforth.py` is the one real-world consumer and it happens to spell the name the
hard-wired way, so **the existing uforth coverage cannot fail on this** — it is
the program the special case was written from. Do not read a green uforth run as
evidence the general path works.
