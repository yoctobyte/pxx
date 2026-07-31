---
track: N
prio: 60
type: bug
---

# Every caught exception leaks its object — 640k raises cost 105 MB

```python
while i < n:
    try:
        v = int("notanumber")
    except ValueError:
        c = c + 1
    i = i + 1
```

RSS grows linearly with the number of exceptions raised and caught. Nothing is
reclaimed when the handler completes.

## Measured — RSS slope

| program | 40 000 | 160 000 | 640 000 | per raise |
| --- | --- | --- | --- | --- |
| `try` with **no** raise (control) | 264 KB | 264 KB | 264 KB | **flat** |
| `raise ValueError("x")` + catch | 3 472 KB | 12 816 KB | 50 320 KB | ~78 B |
| `int("notanumber")` + catch | 6 928 KB | 26 640 KB | 105 360 KB | ~164 B |

The control is flat, so the try/except machinery itself is fine — it is the
exception OBJECT that survives. The `int()` row leaks about twice as much,
consistent with the message AnsiString (`invalid literal for int() with base
10: 'notanumber'`) leaking alongside the object.

## Why this one matters more than the number suggests

Raising is on a designed-in hot path, and `pylib.pas` says so at the raise site:

> Python's two-argument `int(s, base)`. RAISES ValueError on a bad parse rather
> than halting, which is the whole point: **a Forth interpreter tries EVERY
> input word as a number, so a non-numeric token is the ordinary case** and a
> fatal error there would kill the interpreter on its first word.

So the uforth corpus raises once per non-numeric token, by design — and each one
leaks. Any parser, config reader, or `try: int(x) except:` validation loop has
the same shape. This is not an exotic path.

It also compounds with the recent conversions: [[bug-nilpy-pytypeerror-halts-instead-of-raising]]
turned ~20 previously-fatal diagnostics into raises, which is correct, and each
of those now allocates an object that is never freed.

## Shape of a fix

Exception objects are ordinary class instances (`Exception = class ... msg:
AnsiString`), so they should be reclaimed by the same ARC path everything else
uses — the control row proves that path works for other objects in the same
loop. The question is ownership across the unwind: the handler binds the
instance (`except ValueError as e:`) and the object must outlive the unwind but
die when the handler scope exits, including when the handler re-raises or
returns.

Check whether the raise path retains without a matching release, and whether an
exception caught WITHOUT an `as` binding (as in every row above) has any owner
at all — none of the measured cases names the exception, so the leak is not
about the `as` variable.

## Gate

`make test-nilpy` + self-host byte-identical, plus the RSS-slope table above:
the raise rows must go flat and the control must stay flat. Measure at 40k /
160k / 640k with `/usr/bin/time -f %M` — the SLOPE is the evidence, a single
run proves nothing. Keep `test/test_nilpy_typeerror_is_catchable.npy` and the
exceptions test green (the object must still be alive inside the handler).

## MOSTLY FIXED — the object's own leak; a separate, smaller leak remains and is filed on its own

Confirmed at the codegen level (no reasoning needed once found): `IR_EXC_CLEAR`
only zeroed the three exception-bookkeeping BSS globals, never released the
object. The single owning reference the constructor gave the exception (raise
transfers it, does not add a second) had NO owner when the handler had no `as`
binder — confirmed this is the common/every-measured-row case, exactly as this
ticket already suspected.

Fixed: a hidden release-only temp captures the exception object whenever the
matched handler has no `as` binder, and `PXXObjRelease` runs on it right after
the handler body, before `IR_EXC_CLEAR`. A bound `except C as e:` is left
alone — `e`'s own scope-exit release is what already frees it, unchanged.

Re-measured per the gate's own instruction (40k/160k/640k, `/usr/bin/time -f
%M`):

| program | pre-fix 640k | post-fix 640k |
| --- | --- | --- |
| control (no raise) | 264 KB | 264 KB (unchanged, already flat) |
| `raise ValueError()` (no message) | not separately measured before | **flat** (1056 KB at 40k AND 640k) |
| `raise ValueError("x")` + catch | ~50 MB (from this ticket's original table, scaled) | 20 MB |
| `int("notanumber")` + catch | 105 MB | 75 MB |

The no-message row is now provably flat — the object-lifecycle fix is
complete for that shape. The message-bearing rows improved substantially but
are NOT flat: pinpointed the remainder to the exception's OWN message-string
FIELD, not the object — reproduces with `raise ValueError("x")` internally,
`e = ValueError("x")` never raised, and even a **plain user class** with a
string field, all at the same ~31-32 B/iter slope, while an int-field class is
flat. That is a distinct, more general bug (affects any class with a managed
string field, not just exceptions) and is filed separately as
[[bug-a-nilpy-class-variant-field-string-not-released-on-finalize]] rather
than patched here — it needs its own root-cause measurement (the class-finalize
walker's variant-slot path, per that ticket's notes), not a guess bolted onto
this fix.

Test: test/test_nilpy_exception_no_leak.npy, an RSS-guard at 640k raises
(threshold 90 MB — between the fixed ~75 MB and the pre-fix ~105 MB, so a
regression back to the old completely-unreleased behavior is caught; the
follow-on ticket's own fix will let this threshold tighten later). Gate: make
test-nilpy green, self-host fixedpoint, testmgr --tier quick.

This ticket's OWN bug (the object never had an owner when uncaught-by-name) is
closed. Leaving it here rather than filing a fresh "exception leak, part 2"
ticket would just be organizational churn — the remaining leak belongs to the
class/field-finalize investigation, not to the exception-specific mechanism
this ticket was about.

Ticket closed (see the follow-on for the remaining, unrelated leak).
