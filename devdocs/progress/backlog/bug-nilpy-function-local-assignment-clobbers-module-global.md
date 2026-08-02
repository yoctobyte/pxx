---
track: N
prio: 80
type: bug
---

# A function-local assignment WRITES the module global of the same name

- **Type:** bug (NilPy scoping — SILENT WRONG VALUE, wide blast radius) —
  **Track N**
- **Found:** 2026-08-02, by a differential sweep against the CPython oracle.

## Measured

```python
g = 1
def shadow():
    g = 99          # a LOCAL in Python: the module g is untouched
shadow()
print(g)            # CPython 1     pxx 99
```

Same for strings and every other type. Controls behave correctly:

| case | pxx | CPython |
| --- | --- | --- |
| local assigns a DIFFERENT name | `1` | `1` |
| `global g` then `g = 99` | `99` | `99` |
| **local assigns the SAME name** | **`99`** | **`1`** |

Python's rule is unambiguous: assigning a name anywhere in a function makes it
local for the whole function unless `global`/`nonlocal` says otherwise. Here the
function silently mutates module state instead.

## Cause — and the trap in fixing it

An assignment inside a proc resolves its target by ordinary name lookup. When a
module global of that name exists, the lookup finds it and no proc-local is ever
allocated, so the store goes to the global.

**The trap:** `global x` is currently parsed and **discarded**
(`pyparser.inc`, the `nonlocal`/`global` arm: "a scope DECLARATION, parsed and
skipped"). Nothing records it. So `global g; g = 99` works **only because the
leak exists** — remove the leak and `global` stops working too.

The two behaviours are entangled and must be fixed together:

1. **Record `global` (and `nonlocal`) declarations per proc** — there is no
   registry today.
2. **Allocate a proc-local** for any name assigned in the body that is not so
   declared, instead of resolving to the module global.

Doing 2 without 1 breaks every correct `global` user. Doing 1 alone changes
nothing.

## Blast radius — this is why it is not a quick fix

Every NilPy program that assigns, inside a function, a name that also exists at
module scope changes behaviour. Some of it may be relying on the leak — either
knowingly (as a stand-in for `global`) or by accident. The corpus needs a pass
before this lands, and it wants staging: implement the registry, then flip the
allocation behind the full gate with the corpus green.

## Relationship to already-fixed work

The TYPE side of this collision was fixed on 2026-08-01 —
[[bug-nilpy-def-local-assignment-widens-module-global-to-variant]] stopped a
def-local assignment widening the module name's inferred type and stopped
`PyAllocModuleGlobals` pre-creating it. This is the STORAGE side of the same
collision and was not addressed by that work: the type is now right, the
variable is still shared.

Also related: [[feature-nilpy-nonlocal-write-propagation]], which records that a
`nonlocal` WRITE does not propagate because capture is by value. Both are
symptoms of scope declarations being parsed-and-skipped rather than recorded, so
item 1 above serves both.

## Gate

A `.npy` diffed against CPython covering: local shadowing a module global (read
after, and the global read inside the function BEFORE the local assignment,
which CPython makes an UnboundLocalError); `global` single and multiple names;
`global` in a nested def; a local shadowing in one function while another
function reads the true global; and the corpus green.
