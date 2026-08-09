---
track: N
prio: 55
type: bug
---

# Calling a non-callable SEGFAULTS instead of raising TypeError

```python
def get(which):
    if which == 0:
        return 5
    if which == 1:
        return "text"
    return [1, 2]

for i in [0, 1, 2]:
    try:
        get(i)(3)
    except TypeError as e:
        print("TypeError:", e)
```

CPython prints three `'int'/'str'/'list' object is not callable` lines. pxx
**segfaults on the first one**, inside a `try` that names TypeError — so the
program cannot even defend itself.

Confirmed pre-existing (same crash from `stable_linux_amd64/default/pinned`).

## Why the obvious guard cannot work — measured, and it is the whole point

`pyvar_callv0..3` (pyeval.pas) already share a guard, `PyNotCallable`, and it
checks **only `Payload = 0`** (a None binding). Anything with a non-zero payload
is jumped to.

The natural fix — reject variants whose TAG cannot be code — **is not
available**, and the reason is structural: a plain compiled def is represented as
**its code address boxed as a plain INTEGER** (tag 2), and so are a pyeval
closure and a lifted bound-fn (magic-tagged heap objects, also boxed as
integers). So tag 2 is a legitimate callable here, and `5` and `<code address>`
are indistinguishable at the point of call. A deny-list on tag 2 would break
every ordinary call through a value.

I built exactly that guard before measuring this, and it would also have broken
`pyvar_callable_ptr` — whose own comment says it accepts a plain def arriving as
a boxed pointer. Reverted unlanded; recording it so it is not rebuilt.

What CAN be rejected safely is the narrow set never used for a callable here:
double (3), bool (4), char (5), string (6). That fixes `"text"(3)` and `3.5(1)`
but NOT the int case — and the int case is the one that matters, because it is
also how `bug-nilpy-a-class-used-as-a-value-segfaults-or-refuses` crashes.

## So the real fix is a distinct CALLABLE TAG

This is the same root as `project_nilpy_callable_has_three_representations`:
callables have several representations and lean on the integer tag. Giving a
callable value its own variant tag makes this guard a one-liner, makes the
class-as-value crash diagnosable, and removes the "is this int a code address?"
question everywhere it is currently answered by assuming yes.

Until then, `PyNotCallable` could at least reject the four scalar tags above —
strictly better than a segfault, and honest about not covering the int case.
Worth doing only with a test that says which cases it does NOT cover, so it does
not read as fixed.

## Related, found in the same sweep

`c(5)` where `C` defines `__call__` returns a garbage integer rather than
calling it (pinned does the same). Filed here rather than separately because it
is the same dispatcher: `pycallable_obj_is` / tag 7 is the arm that should catch
it.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over calling an
int, a float, a bool, a string, a list, a dict and None; each inside a
`try/except TypeError`; plus controls that a def, a lambda, a bound method, a
def-in-a-list and a `Callable`-annotated parameter all still call correctly.
