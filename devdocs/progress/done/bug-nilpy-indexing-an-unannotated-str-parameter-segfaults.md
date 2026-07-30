---
track: N
prio: 80
type: bug
---

# `def f(s): return s[0]` SEGFAULTS — indexing an unannotated str parameter

```python
def f(s):
    return s[0]
print(f("ab"))        # CPython: a     pxx: SIGSEGV
```

An unannotated parameter is the default way to write Python, and indexing a
string is one of the most common things done with one.

## Scope — measured

| shape | pxx |
| --- | --- |
| `def f(s): return s[0]` with a str argument | **SIGSEGV** |
| `def f(s): return s[0:1]` (slice) with a str argument | `[]` — silently wrong |
| `def f(s: str): ... s[0] ...` (ANNOTATED) | correct |
| `s = "ab"; s[0]` at top level | correct |
| `def f(xs): return xs[0]` with a LIST | correct |
| `def f(d): return d["k"]` with a DICT | correct |
| `def f(s):` then `for c in s:` | correct |

So it is specifically a STRING reaching a variant-typed subscript. Found via a
palindrome function (`if s[i] != s[j]`), which crashed outright.

## Root cause

`pylib.pas`, `pyvar_getitem`:

```pascal
function pyvar_getitem(const v: Variant; const key: Variant): Variant;
var o: TObject; ki: Int64;
begin
  o := TObject(pyvarobj(v));        { <-- cast BEFORE any tag check }
  if o is TPyDict then ...
```

The tag is never examined. For a variant holding a string (VT_STRING, tag 6)
`pyvarobj` hands back the string's handle, and the `is TPyDict` test then
dereferences a VMT pointer out of string bytes.

Its sibling `pyvar_slice`, ten lines below, gets this right:

```pascal
  if pyvartag(v) = 6 then
    Result := pystr_slice(pystr_of(v), lo, hi)     { str -> boxes to VT_STRING }
  else if pyvartag(v) = 7 then
  ...
```

Same shape as the recurring pattern in this repo: one ownership/identity
predicate written inline in two places, and one place gains a case the other
lacks. `pyvar_getitem` needs the tag-6 arm (and tag 5, a char), and must not
cast at all when the tag is not 7.

The slice returning `[]` rather than `"a"` is a second, separate defect on the
same path — `pyvar_slice` DOES handle tag 6, so the wrong answer comes from
further up (probably the frontend choosing a list-slice lowering for a
variant-typed receiver). Re-measure it after the getitem fix rather than
assuming they share a cause.

## Not a regression

Reproduced identically on the stable compiler from 2026-07-27, before this
session's work.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` covering the table
above with CPython's own output, and the palindrome function end to end. Keep
the list, dict, annotated and top-level rows as guards that the working paths
are untouched.

## Log
- 2026-07-30 — resolved, commit ab2a9ecd7.
