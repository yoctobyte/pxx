---
track: N
prio: 55
type: bug
status: done
owner: claude-AN
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

## Resolution (2026-08-11) — 7 of the 8 shapes, and the 8th is measured, not guessed

### The ticket's blocking claim was half right, and the half that was wrong is what unblocked it

The ticket said a deny-list is impossible because "a plain compiled def is
represented as its code address boxed as a plain INTEGER (tag 2), so `5` and a
code address are indistinguishable." That reasoning was sound but the premise
was never measured against a corpus. So I probed the guard — print
`VType` on entry, run every `.npy` in `test/`:

| tag | samples | what it is |
| --- | --- | --- |
| 10 | 245 | lifted bound-fn |
| 2 | 106 | plain def code address |
| 9 | 12 | pyeval closure |
| 0 | 2 | None (already raised) |

**Tags 1, 3, 4, 5, 6 and 7 appear ZERO times.** Nothing callable is ever boxed
as one. And the shapes in the repro land on exactly those tags — `5`→1,
`"text"`→6, `3.5`→3, `True`→4, list/dict/tuple→7, `None`→0. So a refusal on
those cannot break a working program, and every one of them was a live
segfault. The ticket's "the four scalar tags are all that CAN be rejected, and
the int case is the one that matters" undercounted: `5` is tag 1 and *is*
rejectable.

### Then the obvious over-claim got falsified before it shipped

The tempting conclusion — "ints are tag 1, defs are tag 2, so refuse 1" — is
luck, not a rule. `VT_INT=1` / `VT_INT64=2` is an integer **width** distinction
and says nothing about callability. Tested directly rather than assumed:

| expression | tag |
| --- | --- |
| `5`, `-7`, `len("abcd")` | 1 |
| `3 + 4`, `2**40`, `int("99")` | **2** |
| `2**70` | 8193 (promo) |

So `(3 + 4)(x)` still faults, and no tag test can fix it. That is the honest
residual, split out as
`feature-nilpy-a-callable-value-needs-its-own-variant-tag` with this table so
nobody re-derives it — and the test carries a comment saying which case it does
NOT cover, exactly as this ticket asked, so it cannot read as fully fixed.

### The tag-7 arm, kept deliberately narrow

An instance is callable iff its class defines `__call__`. A tag-7 payload with
no `__call__` now raises (list, dict, tuple — three of the eight). One that HAS
`__call__` falls through to the old path instead of being refused: it currently
returns a garbage integer, and refusing it would turn a wrong value into a
wrong error, which is a regression. That dispatch is
`bug-nilpy-a-call-dunder-on-an-instance-is-not-dispatched` — where I noted that
`pylib.pas` already contains `PyNotCallableError`, written for this arm and
never wired to anything.

### Verified

`test/test_nilpy_calling_a_non_callable.npy`, output byte-identical to CPython:
all 8 shapes raise a catchable TypeError, and 7 controls (def as a value,
lambda, bound method, def in a list, def in a dict, class as a value, def
passed as a parameter) all still call. Gate: `tools/gate.sh quick` GREEN +
`make test-nilpy`. No re-pin — `pyeval.pas` is a compiled program's runtime and
is not linked by the compiler itself.

## Log
- 2026-08-11 — resolved, commit PENDING-COMMIT.
