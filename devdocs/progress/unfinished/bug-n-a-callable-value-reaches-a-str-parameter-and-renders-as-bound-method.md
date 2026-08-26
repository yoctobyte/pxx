---
slug: bug-n-a-callable-value-reaches-a-str-parameter-and-renders-as-bound-method
track: N
prio: 70
status: working
owner: frank1-72
---

# A callable value is silently accepted where `str` is declared, and no longer compares equal to itself — bisected to `9bbbbef6c`

Two of the 13 jobs in `regression-cascade-21f098e32a95`, one family. **Silent
wrong value**, not a crash: the refusal that used to catch it is gone.

## 1. The refusal disappeared (`test_nilpy_callable_to_str_param_fails`)

`test/test_nilpy_callable_to_str_param_fails.npy` asserts a COMPILE ERROR:

```python
def f(s: str) -> str:
    return s
class C:
    def m(self):
        return 1
c = C()
print(f(c.m))
```

Expected: `expects text for parameter "s"`. Today it compiles clean and prints

```
<bound method at 0x75459ea00048>
```

which is the exact shape `bug-nilpy-bound-method-coerced-to-string` was filed
for — the `{code, receiver}` pair travelling on as text, which is how Tk came to
evaluate a callback as a script and hang inside the event loop.

**Bisected** (clone at `$SCRATCH/bisect`, seeded from the pinned binary, one
`make compiler/pascal26` per step):

    9c5148087  GOOD (refused)
    e78cc5882  GOOD (refused)
    9bbbbef6c  BAD  (compiles)      <- feat(nilpy): a call through a callable value fills the callee's defaults
    9e711a681  BAD
    HEAD       BAD

## 2. A stored callable no longer compares equal to itself (`lib-test#src:test/lib_mimic_xml_etree_elementtree.npy`)

```python
import xml.etree.ElementTree as ET
CT  = ET.Comment("asd").tag
com = ET.Comment("hi")
print("sentinel:", com.tag == CT)      # CPython: True.  PXX: False
```

`Comment("x").tag IS Comment` is the one identity `lib/rtl/mimic_xml_etree_elementtree.py`
documents as having to be exact, because html5lib captures it once
(`treewalkers/etree.py:16`) and compares every node against it. It fails, so the
walk treats a comment as an element and dies:

```
comment_tag_is_the_sentinel=FAIL got False want True
second_comment_same_sentinel=FAIL got False want True
comments_walk_as_comments=FAIL got [<bound method at 0x…>, 'body'] want ['comment', 'body']
Unhandled exception: TypeError: can only concatenate str (not "method") to str
```

## Why the lib-test job only went red now — and what that means for the range

**This half is NOT caused by anything in the cascade's 261-commit range.** The
job builds with `$(PXX_STABLE)`, and:

- the pinned binary from *before* the range runs the test green;
- a compiler built from source at the range's **last good** sha `9bfb7fcfac03`
  fails it;
- so does one built at `7bebd63fa`, the commit that ADDED the test.

So the defect was already in the source and the job was green only because the
pin lagged behind it. **`cc20f7101` (pin v365) is what exposed it, not what
caused it** — and the same is true of anything else this pin newly surfaces. The
callable half above (`9bbbbef6c`) is inside the range and was caught immediately
because that job builds with `$(COMPILER)`, i.e. HEAD.

## Repro

    make compiler/pascal26
    ./compiler/pascal26 test/test_nilpy_callable_to_str_param_fails.npy /tmp/x   # must FAIL to compile
    ./compiler/pascal26 -Fulib/rtl test/lib_mimic_xml_etree_elementtree.npy /tmp/m && /tmp/m | tail -1
    # want: MIMIC-XML-ETREE OK

## Note for whoever takes it

Two symptoms, one subject: what a callable VALUE is once it is stored, passed
and compared. Treat them as one root cause until a repro proves otherwise — the
`str`-parameter refusal and the identity comparison both hang off the same
representation, and the second predates the first, so fixing only `9bbbbef6c`
will leave the mimic job red.

*Filed by frank2-C during cascade triage; not claimed. Track N ground — the
standing mandate defers N features and bugs, but a REGRESSION is worked at the
priority of being red regardless of subject.*

---

## Worked by frank1-N (2026-08-25) — both halves plus the leak underneath

Landed on `dev`, gate quick GREEN at `d37573c69` (self-host fixedpoint + testmgr
quick, on a box with Track T running).

### 1. The refusal — `bf5a9ba61`

The bisect to `9bbbbef6c` is correct, and the mechanism is a NAME WHITELIST that
went blind. `PyNodeIsCallableValue` recognises a callable by the name of the
pylib call that constructed it, spelled out one at a time:

    (nm = 'pybound_new') or (nm = 'pybound_new_star') or ...

`9bbbbef6c` added `pybound_new_sig` and switched BOTH producers
(`PyMakeFuncValueFor`, `PyMakeBoundMethod`) onto it, so from that commit on
every bound method the frontend builds arrives under a name the predicate had
never heard of. Nothing about the VALUE changed — only the label.

Matched by prefix now: any `pybound_new<suffix>` is a `{code, recv}`
constructor. The `pyclosure_*` / `pyboundfn_*` arms deliberately stay explicit —
those families also hold predicates and dispatchers (`pyclosure_is`,
`pyboundfn_call_ptr`) that do NOT produce a callable, so a prefix over-claims
there.

### 2. The leak — `293d70509`. NOT what the ticket note assumed.

`str(f)` on a plain def printed a decimal, but **not** because the value was
VT_INT64 and **not** because tag 12 was constructed nowhere. Measured with
`pyvartag`:

    print(pyvartag(g))    # 12   <- argument position
    a = g; print(pyvartag(a))  # 8    <- after an assignment

Tag 12 exists, the backends stamp it (`IRSrcIsCallable`), and all three
rendering entry points already route it through `PyCallableStr`. The value
simply never got boxed on one of the two roads: `ParseFactorCore`'s
bare-callable arm handed back an `AN_PROCADDR` typed **tyPointer**, and a
tyPointer argument never reaches a `const v: Variant` parameter — overload
matching binds it to `pystr_of(Int64)`, which formats the code address as a
number. The callable machinery was never consulted.

That arm was a COPY of `PyMakeFuncValueFor`'s body (safe-overload pick,
return-side wrapper, nested-def closure) and had drifted twice: the wrapper was
still capped at `ParamCount = 1` while the assignment path had been widened to
any arity, and the plain case never reached the `pybound_new` pair at all. It is
now one line of delegation — the second implementation is deleted, not patched
(`devdocs/dev/normalise-dont-special-case.md`).

`test_nilpy_function_value_repr` grows the case its own header explicitly
excluded ("NOT covered: a plain compiled def used as a value ... it still prints
a number"); the whole file now matches CPython byte for byte.

### 3. The compensating arm — `d37573c69`, removed, measured first

`PyVarEqCallable`'s int arm ("an int opposite a real callable is a code
address") is gone. Instrumented to report every time it answered **True**, it
answered True **zero** times across the uforth smoke, four ANS word sets
(exceptiontest / coreexttest / stringtest / localstest, all byte-identical to
the CPython oracle), `lib_mimic_xml_etree_elementtree`, and eleven
callable-value tests — and zero with the leak still OPEN too, built at
`293d70509^`. So it was dead code before the fix as well as after, which is why
this is a removal rather than a bet on the fix upstream of it. It also carried a
divergence: CPython says a function is never equal to a number.

### Repros

    ./compiler/pascal26 test/test_nilpy_callable_to_str_param_fails.npy /tmp/x
    # -> error: Nil Python: f expects text for parameter "s" ...   (exit 1)  GREEN

    ./compiler/pascal26 -Fulib/rtl test/lib_mimic_xml_etree_elementtree.npy /tmp/m && /tmp/m | tail -1
    # -> MIMIC-XML-ETREE OK                                                  GREEN

### Pin

`d37573c69` touches `compiler/builtin/pylib.pas`, so Track B's `lib-test` does
not see the equality change until someone pins. Flagged to `frank1-72`.
