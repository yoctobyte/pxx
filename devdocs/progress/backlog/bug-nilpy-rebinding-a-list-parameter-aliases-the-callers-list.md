---
track: N
prio: 58
type: bug
blocked-by: []
summary: "A list rebound with `+` and then RETURNED loses its value: returning a rebound PARAMETER yields the empty list, returning a LOCAL built by `out = out + [i]` in a loop yields a raw pointer printed as a 15-digit int, and in a recursion the rebinding leaks into the caller's list so a DFS prints '0-1-2-2-1-2' instead of '0-1-2'. append() and a copy-to-another-local are both correct"
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

## Gate

A `.npy` diffed against CPython: every row of the table above, the recursive
walker (which is the shape that fails loudest), a str parameter rebound the
same way (`s = s + "x"`), a dict parameter (`d = d | {...}` / a copy), and the
caller's list asserted unchanged after each call.
