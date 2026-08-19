---
slug: bug-n-a-callable-value-reaches-a-str-parameter-and-renders-as-bound-method
track: N
prio: 70
status: urgent
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
