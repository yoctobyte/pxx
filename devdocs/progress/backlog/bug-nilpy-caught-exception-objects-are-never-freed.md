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
