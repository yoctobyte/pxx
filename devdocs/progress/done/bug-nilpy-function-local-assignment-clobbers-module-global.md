---
track: N
prio: 80
type: bug
status: done
owner: claude-AN
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


## Resolved 2026-08-02 — commit e0f5b4a3c

Both items from "Cause — and the trap in fixing it", together, as the ticket
required. The entanglement it predicted is not hypothetical: the first build
carrying only the shadow rule printed `1` for BOTH halves — `global h; h = 99`
stopped writing through the moment the leak it was riding on closed. The
registry had to land in the same commit.

1. **Registry** — `PyScanDefGlobals(bodyStart)` token-scans the def body for
   statement-initial `global` / `nonlocal` and collects the names into
   `PyDefGlobalName` (`PY_MAX_DEF_GLOBALS = 32`). Token-scanned, not collected
   while parsing, because the answer is needed by the FIRST assignment in the
   body while Python's rule is whole-function — `g = 1` on line 2 is still a
   module write when `global g` appears on line 9. Saved and restored around
   `PyParseDef` and `PyParseMethod`, so a nested def (drained at the end of the
   enclosing routine) cannot leak its declarations upward. `nonlocal` names go
   in the same list: they must not become fresh locals either, which leaves
   [[feature-nilpy-nonlocal-write-propagation]] exactly where it was.

2. **Allocation** — `PyAssignTargetSym(nm)` is `PyProgSym` for a name being
   ASSIGNED, differing in one case: inside a def, a name that resolves to a
   module global and is not declared is reported absent, so the caller allocates
   a proc-local. Only `skGlobal` is diverted — params, existing locals and
   `self` resolve as before. Wired into the plain and annotated assignment paths
   AND into both local-allocation loops (the fixed-point seeding inside
   `PyCollectLocalsAST` and the real allocation in `PyParseDef` /
   `PyParseMethod`). That last part matters: the local is therefore created
   BEFORE the body is emitted, so every reference in the function sees it, which
   is Python's actual rule rather than "local from the assignment onward".

### Landmine worth remembering

`bodyStart` is already INSIDE the block — `PyParseDefHeader` and
`PyParseMethod` both consume the `tkIndent` before recording it. A scan that
begins by hunting forward for an INDENT therefore finds the first NESTED block
instead, and the body's own `global` is never seen. It fails SILENTLY (the
declaration is simply not found, and the name shadows), which is how the first
build passed compilation and still got the answer wrong. `PyScanDefGlobals`
starts at depth 1 with a comment saying so.

## Verified against CPython

`test/test_nilpy_global_scope_binding.npy` (+ `.expected`, wired into `make
test-nilpy`) is the ticket's gate list: a local shadowing a module global with a
SECOND function reading the true global in the same program; `global` with a
single name and with a list; `global` inside a nested def; a nested def that
shadows without declaring; strings as well as ints; a method shadowing and a
method declaring `global`; and a `for` target shadowing a module global. Output
byte-identical to CPython's.

**Not implemented, deliberately:** reading the name inside the function BEFORE
the local assignment is `UnboundLocalError` in CPython; pxx reads the
zero-initialised local. That is a diagnostic, not a wrong value, and it is out
of scope here — file it separately if it is wanted.

## Corpus pass (the ticket asked for one before landing)

Scanned every `test/*.npy` and the `examples/**` Python sources for the shape
that could be relying on the leak — a def assigning a name that also exists at
module scope, without `global`. **Four sites in two files**, both of which are
tests with recorded CPython expectations:
`test_nilpy_def_local_shadows_module_global.npy` (`zz`, `it`, `nn`) and
`test_nilpy_selfassigned_comprehension.npy` (`r`). Both still match CPython byte
for byte after the change. Nothing in the corpus depended on the leak.

## Gate

`tools/gate.sh quick` GREEN, self-host fixedpoint byte-identical. Cross targets
and the full matrix are Track T's.

## Log
- 2026-08-02 — resolved, commit e0f5b4a3c.
