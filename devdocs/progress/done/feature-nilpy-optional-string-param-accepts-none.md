---
summary: "nilpy: passing None to an Optional[str] / str|None PARAMETER does not match the overload"
type: feature
track: N
prio: 50
owner: claude-A-N
---

# nilpy: `f(None)` where the parameter is `Optional[str]`

- **Type:** feature (Nil-Python frontend, Optional lowering) — **Track N**
- **Status:** done
- **Opened:** 2026-07-26 — found while adding PEP 604 unions
  ([[feature-demo-songformatter-pxx-target]]). PRE-EXISTING: reproduces on the
  pinned stable with the `Optional[...]` spelling, so it is not a union-specific
  problem.

## Repro

```python
from typing import Optional
def g(x: Optional[str]) -> str:
    if x is None:
        return "none"
    return x
print(g("a"), g(None))
```
```
error: no overload of g matches these arguments
  argument types: (Pointer)
```

`str | None` behaves identically, by design — unions get Optional's exact
treatment. RETURNING None from such a function works; only passing it in fails.

## Why

An `Optional[str]` parameter is typed AnsiString (Optional widens `str` to
AnsiString), and `None` arrives as a nil Pointer, which does not match. The
return path works because a return annotation widens further, to a real variant,
so None and a legitimate value stay distinct.

## Shape

Type an Optional PARAMETER the way an Optional RETURN is typed — a variant, so
None is VT_EMPTY rather than a nil pointer of the wrong type — or accept a nil
Pointer argument for an Optional-annotated string parameter. The first is more
consistent with what the return path already does.

## Gate

`make test-nilpy` green with a `.npy` case passing None and a real value to
Optional params of str / int / a class type, diffed against CPython, + `--tier
quick` + self-host byte-identical.

## Recon 2026-07-31 — the repro has changed shape; still broken, differently

Re-ran the ticket's own repro on current HEAD. It no longer hits the compile
error ("no overload of g matches these arguments") — `g(None)` now COMPILES.
But the runtime answer is wrong in a new way:

```
print(g("a"), g(None))   # CPython: a none     pxx: a None
```

`g(None)` is being called (not rejected), but inside `g`, `x is None` does not
take the True branch — the function falls through to `return x`, and PRINTING
`x` renders the text `"None"` (four characters, capital N), not the identity
check's own None marker. So whatever coercion now lets the call through is not
the `pynone()` VT_EMPTY-boxing fix `IRLowerCallArg` already has for a VARIANT
parameter (`ir.inc` ~line 2208, "Python's `None` reaches here as the nil
POINTER literal... f(None) then printed 0") — that block is gated on the
PARAMETER being `tyVariant`, and `Optional[str]` maps to `tyAnsiString`
(PyAnnTypeAt), not variant, so it never fires here. Something ELSE now accepts
a nil-pointer argument against an `AnsiString` parameter and turns it into the
text "None" rather than a nil string handle — not yet located. `IRLowerCallArg`
is a very large, historically fragile function (each of its many special
cases documents a specific past regression); finding the exact coercion
without measuring it directly (PXXDBG a.ir on the call site, or bisecting
which recent commit changed this from a compile error to a silent wrong
value) risks a guess, which the project's own debugging playbook warns
against. Left for the next session with time to measure it properly rather
than patch blind.

Not fixed. Recon only — see above for what changed and what still needs
locating.

## 2026-08-10 — REMEASURED: the symptom changed, and got WORSE

The repro above no longer produces the recorded error. It **compiles**, and
then answers wrongly with no diagnostic at all:

```
CPython : a none
pxx     : a None
```

Probed one level down (`print` inside `g`):

| | `g("a")` | `g(None)` |
| --- | --- | --- |
| CPython `x is None` | False | **True** |
| pxx `x is None` | False | **False** |
| CPython `x == None` | False | **True** |
| pxx `x == None` | False | **False** |

So the argument arrives, the overload now matches — that half of the ticket is
fixed — but **a None passed to an `Optional[str]` parameter does not compare
equal to None inside the callee**, by either `is` or `==`. The `if x is None`
branch never runs, `return x` returns the None, and it prints as `None`.

**Controlled:** byte-identical on `stable_linux_amd64/default/pinned`, so this
is pre-existing and NOT a consequence of the 2026-08-10 overload-selection work
(`PyPickOverloadByArgTypes`) landing the same day. The old "no overload matches
these arguments" error is simply gone; whatever removed it left the value
mis-typed rather than mis-matched.

This changes the ticket's priority shape: a loud compile error became a **silent
wrong answer**, which is the failure class `devdocs/dev/debugging-playbook.md`
calls the expensive one. Both `is` and `==` failing together points at the
argument's runtime TAG on entry — the None is presumably arriving as a typed
null (the old error named `Pointer`) rather than as a None-tagged variant, so
the tag test fails. **Measure the tag on entry (`pyvartag`) before changing
anything** — that is one probe and it settles the direction.

Still parked; re-filed measurement only, no code changed.

### The tag probe — one measurement, root identified

```python
def g(x: Optional[str]) -> str:
    print("  tag:", pyvartag(x))
g("a")    ->  tag: 6
g(None)   ->  tag: 6          <-- should be 0
n = None; pyvartag(n) -> 0
```

**The None is converted to a STRING at the call site.** It arrives inside `g`
tagged VT_STRING (6), identical to `"a"`, while a bare `None` is VT_EMPTY (0).
Nothing inside the callee is wrong: `is None` and `== None` correctly answer
False about a value that genuinely is no longer None by the time they see it.

So this is an ARGUMENT-COERCION bug, not a comparison bug. `Optional[str]`
evidently lowers the parameter to the plain `str` arm, and the call converts the
argument to it — which is also the tidiest explanation for how the old "no
overload matches" error disappeared without anyone fixing None handling: the
argument now converts instead of failing to match, and converting is exactly
what destroys the None.

**The fix therefore belongs at the Optional lowering / argument conversion, not
at the `is None` test.** An `Optional[T]` parameter has to stay a variant (or
otherwise keep its tag) rather than collapse to `T`; anything that fixes
`is None` inside the callee without fixing the tag would be papering over a
value that arrived wrong.

Note the interaction to check when this is picked up: an `Optional[str]`
parameter that stays a variant changes which overload it is, so re-run it
against `PyPickOverloadByArgTypes` (landed 2026-08-10) — a variant parameter now
exactly matches a variant argument, which is likely to be what makes the
matching work honestly rather than by conversion.

## DONE 2026-08-13 — one line, exactly where the parked measurement said

The parked note did the whole job: the `pyvartag` probe showed the argument
arriving inside the callee tagged VT_STRING, identical to `"a"`, so the fault
was the ARGUMENT and not the `is None` test, and the fix belonged at the
Optional lowering. It did.

`Optional[T]` in PARAMETER scope now yields a variant when T is `str`, as it
already did for `Optional[int]` in RETURN scope and for the same reason: the
target type has no room for the distinction. A NilPy str that is None is a nil
AnsiString handle — and so is `""`
([[bug-nilpy-empty-str-and-none-are-the-same-value]]) — so collapsing
`Optional[str]` to `str` let the call site convert the None on the way in, which
is what destroyed it.

Measured after: `g(None)`, `g("")` and `g("a")` all answer CPython's values, in
every shape swept — a bare parameter, one with a `None` default, an
`Optional[str]` beside a plain `str` parameter, a constructor storing it in a
field, a None held in a local first, and an annotated `opt: Optional[str] =
None`. The `""` rows are the point: a fix that boxed "a nil str handle" as None
would pass every None row and fail those, which is how the attempt recorded in
this ticket's history failed.

The interaction this ticket flagged — `PyPickOverloadByArgTypes` now seeing a
variant parameter where it used to see a str — was re-run: the 29-file
NilPy annotation / str / None / typing test family is unchanged.

Test `test/test_nilpy_optional_str_none.{npy,expected}` (`.expected` from
CPython), wired into `test-nilpy`. Gate: self-host fixedpoint + `gate.sh quick`
GREEN.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
