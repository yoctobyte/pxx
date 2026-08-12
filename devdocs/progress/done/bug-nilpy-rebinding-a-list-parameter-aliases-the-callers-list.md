---
track: N
prio: 58
type: bug
blocked-by: []
summary: "A list rebound with `+` and then RETURNED loses its value: returning a rebound PARAMETER yields the empty list, returning a LOCAL built by `out = out + [i]` in a loop yields a raw pointer printed as a 15-digit int, and in a recursion the rebinding leaks into the caller's list so a DFS prints '0-1-2-2-1-2' instead of '0-1-2'. append() and a copy-to-another-local are both correct"
status: done
owner: claude-AN
---

# A list rebound with `+` loses its value when returned

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-12, differential bug hunting against CPython (a graph
  walker — the shape that uses this idiom).

`p = p + [x]` is *the* Python idiom for "extend without touching the caller's
list", and it is what every recursive path/accumulator walk is built on.

## Symptom 1 — returning the rebound parameter gives the empty list

```python
def a(p):
    p = p + ["x"]
    return p

print(a(["1"]))        # pxx: (empty line)     CPython: ['1', 'x']
```

## Symptom 2 — in a recursion it accumulates across sibling calls

```python
out = []

def walk(node, path):
    path = path + [node]
    if node >= 2:
        out.append("-".join([str(x) for x in path]))
        return
    walk(node + 1, path)
    walk(node + 1, path)

walk(0, [])
print(out)
```

| | |
| --- | --- |
| CPython | `['0-1-2', '0-1-2', '0-1-2', '0-1-2']` |
| pxx | `['0-1-2', '0-1-2-2', '0-1-2-2-1-2', '0-1-2-2-1-2-2']` |

The second call at each level sees what the first one appended — i.e. the
callee's rebinding reached the caller's list, which is exactly what `+` must
never do.

## Symptom 3 — a LOCAL built with `+` in a loop returns a raw POINTER

Not a parameter at all, and probably the sharpest repro of the three:

```python
def build(n):
    out = []
    for i in range(n):
        out = out + [i]
    return out

print(build(4))        # pxx: 134196393675032     CPython: [0, 1, 2, 3]
```

| variant | pxx |
| --- | --- |
| `out = []; out = out + [1]; return out` (no loop) | correct — `[1]` |
| the loop version above | **a pointer printed as an int** |
| `out.append(i)` in the loop | correct |
| the loop version returning `len(out), out` | correct — `(2, [0, 1])` |
| `out = [9]` then the same loop | **a pointer** |

A 15-digit integer where a list was expected is what a list HANDLE looks like
printed as an int, so the return has lost the type as well as (or rather than)
the value — which is the same lost-ownership story as symptoms 1 and 2, and
almost certainly the same fix.

## The boundary — measured

| shape | result |
| --- | --- |
| `p = p + ["x"]; return p` | **empty** |
| `p = p + ["x"]; q = p; return q` | correct |
| `p = ["z"]; return p` (rebound to a fresh literal) | correct |
| `p = p + ["x"]; return len(p), p` (inside a tuple) | correct |
| `p = p + ["x"]; print(p)` (used, not returned) | correct |
| `q = p + ["x"]; return q` (a NEW local, not the parameter) | correct |
| `p.append("x"); return p` (genuine mutation) | correct |
| the same rebinding at MODULE level | correct |
| a NON-recursive def called twice with the same list | correct |

So the value is computed correctly and is right *inside* the body; two things
go wrong only for the parameter slot itself — the RETURN of it, and its
lifetime across a recursive call.

**Only a list.** The same rebinding of a **str** parameter (`s = s + "b"`), a
**dict** (`m = dict(m)` then a write), an **int** (`n = n + 1`) and a **tuple**
(`p = p + (1,)`) are all correct, caller unchanged. That narrows it to the list
`+` lowering and how its result lands in a parameter slot, rather than to
parameter binding in general.

## Reading

Both symptoms fit one cause: `p = p + [...]` writes the new list into the
parameter's own slot without giving the slot a fresh owned reference. The
return then hands back something already released (empty), and a recursive
call re-enters with the caller's slot still pointing at the list the callee
grew. The `q = p` control working is the tell — a plain local gets the
retain the parameter slot does not.

Start at how a parameter binding is assigned in `PyParseStatement`'s
assignment path versus a local, and what the list `+` lowering returns
(a fresh TPyList or the left operand grown in place — the recursion symptom
says the latter is at least reachable).

## 2026-08-12 — re-measured after the field-typing fix; symptom 3 is an ABI mismatch

Symptom 3 narrowed a long way, and it is not a rendering bug:

| def body | result |
| --- | --- |
| `out = []; out = out + [1]; return out` (NO loop) | correct — `[1]` |
| `out = [1]; out = out + [2]; return out` (no loop) | correct |
| the same two lines inside a `for i in range(2)` | **pointer** |
| ... inside a `for i in [0, 1]` | **pointer** |
| ... inside a `while` | **pointer** |
| `out.append(i)` in any loop | correct |

So the LOOP is the trigger, not `+`. And the value is genuinely broken, not
just its rendering: with `x = f()`, `len(x)` is 2 and `type(x).__name__` is
`list` — the runtime tag is right — while `x[0]` reads **-1346371488** and
`print(x)` shows the handle. A correct tag with a garbage element is what a
caller reading the result from the wrong place looks like.

That points at the signature/frame disagreement this file warns about
repeatedly: the shell pre-pass and the body pass inferring different return
types for the same def. `PyInferDefRetType`'s bare-ident chase folds a
self-referential accumulator through `chainCur` (the `acc = acc + chr(97)`
note), and the loop is what makes the two passes see different things —
outside a loop the same two assignments type correctly in both.

**Diagnostic shortcut for the next session:** a def whose result is used as a
VALUE somewhere in the module (`for fn in [f, g]:`) prints correctly, because
`PyDefUsedAsValue` normalises its return to a variant and the disagreement
disappears. That is a clean A/B — same body, one line elsewhere in the file
flips it — and it says the bug is in the return TYPE, not in the list.

## Gate

A `.npy` diffed against CPython: every row of the table above, the recursive
walker (which is the shape that fails loudest), a str parameter rebound the
same way (`s = s + "x"`), a dict parameter (`d = d | {...}` / a copy), and the
caller's list asserted unchanged after each call.

## 2026-08-13 — FIXED. Three symptoms, TWO causes, and the ticket's own boundary was an artifact

Both causes were found by varying the shape until the boundary moved, not by
reading the code the ticket pointed at.

### Cause 1 — the return TYPE, and it is not the loop (symptoms 1 and 3)

The recorded diagnosis said the LOOP was the trigger. It is not: `PXXDBG=n.ret`
(added here) prints the inferred result of each def, and the boundary is a
one-element list literal used as an OPERAND.

| body | inferred result |
| --- | --- |
| `out = out + [1]` (int literal) | tyClass rec=39 — TPyList, right |
| `out = out + [i]` (an ident) | **tyClass rec=0** — a class result with NO class |
| `out = out + [i, 1]` | right, **by accident** — the int widened the assignment to an int default, so it was ignored and the earlier `out = []` survived |

Two independent holes, both in the token-only inference:

- **The chain fold dropped the class identity.** `PyInferDefRetTypeScan` folds a
  self-referential accumulator through `chainCur`, but `PyWiden` folds a
  *TTypeKind* and knows nothing of `PyInferLastCi` — so the chain said "still a
  class" while the re-scan of `out + [i]` had just cleared the class to -1. The
  def registered a CLASS RESULT WITH NO CLASS and the caller read the TPyList
  handle as a bare pointer: a 15-digit integer. Fixed by carrying `chainRec`
  beside `chainCur`.
- **A list/dict literal as an OPERAND was walked element by element.** The
  literal arms of `PyInferExprType` only fire when the expression STARTS with
  the bracket, so `p + ["x"]` took its type from the `"x"` and inferred
  AnsiString — that is symptom 1, where a def returning a list declared a
  string result and handed back the empty string. Now folded as its container
  type with the group skipped, the way the subscript arms already skip theirs.
  Literal-vs-subscript is decided by the preceding token, because `f(x)[0]`
  leaves the walk sitting on a `[`.

### Cause 2 — a rebound variant PARAMETER was the caller's own slot (symptom 2)

The ticket's boundary table says "only a parameter, only in a recursion". Both
halves are artifacts of static typing. Measured:

| the CALLER's variable | callee's `p = p + [9]` reaches it? |
| --- | --- |
| a module global holding a list literal | no |
| a def local holding a list literal | no |
| a **variant** local (`z = mk(1)`) | **yes** |
| a **variant** global | **yes** |
| a parameter | **yes** |

The three "no" rows are statically tyClass, so the call site boxes them into a
temp and the callee's write lands in the temp. Every genuinely VARIANT caller
variable is corrupted, recursion or not — this dialect passes a variant
const-by-REF, so the parameter symbol IS the caller's storage and `p = ...`
stores through it. Python rebinding is local, always.

Fixed callee-side: a variant parameter whose body rebinds it is RENAMED to
`$byref.<name>` and an ordinary local takes the name, seeded from the parameter
at the top of the body. Renaming rather than teaching the assignment path about
parameters is the point — every read, every write, the locals inference and the
capture scan then see one ordinary local, so no second path can disagree.
Both parameter paths needed it (`PyParseDef` and `PyParseMethod` are separate
code; the method path was still wrong after the def path was fixed).

Augmented assignment counts as a rebind and is correct that way: `p += [x]`
mutates the list in place through the copied handle, so the caller sees it, while
`p += 1` rebinds the private slot and the caller does not — both match CPython.

**A CAPTURE is not a parameter.** Nested defs receive the enclosing frame's
names as extra params; giving one a private slot broke `nonlocal`
(`test_nilpy_selfassigned_comprehension` went from `(2, 'done')` to `(2, None)`),
which is why the copy is restricted to the def's OWN declared parameters.

### Gate

`test/test_nilpy_rebinding_a_parameter_is_local.npy` + `.expected` from CPython,
wired into `make test-nilpy`: all three symptoms, every caller-variable kind
above, the recursive walker, a method, genuine `append` mutation, `+=` on a list
vs an int, and str/int/tuple/dict parameter controls. `make test-nilpy` green,
`gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit 628764a23.
