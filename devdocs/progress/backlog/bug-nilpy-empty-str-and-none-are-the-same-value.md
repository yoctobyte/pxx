---
track: N
prio: 40
type: bug
blocked-by: decide-nilpy-none-str-representation
summary: "`\"\" is None` answers TRUE for a NilPy str: Pascal's empty AnsiString IS a nil handle, so the None sentinel and the empty string are indistinguishable — contradicting pylib's own comment that they are not."
---

# `""` and `None` are the same value for a NilPy str

```python
class E:
    def empty(self) -> Optional[str]:
        return ""
    def plain(self) -> str:
        return ""

print(E().empty() is None)   # CPython False   pxx True
print(E().plain() is None)   # CPython False   pxx True
print(len(E().empty()))      # both 0
```

## Why it matters

NilPy's whole None-for-str design rests on the two being distinguishable.
`pystr_none` returns a nil handle and `pystr_is_none` tests `Pointer(s) = nil`,
and pylib's comment states the assumption outright:

> a NilPy str that is None has a nil handle, a real string (including "") does
> not

Measured, that is FALSE — an empty AnsiString is nil in this runtime, so every
`is None` test on a str also fires for `""`. Ordinary Python code branches on
exactly that difference (`if s is None:` versus `if s == "":`), and here both
answer the same.

It also bounds what any fix in this family can do: a bridge that boxes "a nil
str handle" as None — which is the obvious way to make a host method's None
survive — would silently convert every returned `""` into None. That approach
was tried and abandoned for this reason while fixing
[[bug-nilpy-return-none-from-a-str-returning-def-yields-the-text-None]].

## PRE-EXISTING

Identical under `stable_linux_amd64/default/pinned`.

## Shape of the fix

The sentinel needs a representation that "" cannot collide with. Options worth
weighing rather than guessing between: a distinguished non-nil handle for None;
a separate variant tag for a None-str; or making str-typed Optionals variants
outright and accepting the cost. This is a model decision — consider a Track U
`decide-` ticket rather than picking one in passing, since
[[bug-nilpy-non-ascii-string-surface-measured]] and
[[bug-nilpy-encode-ignores-the-codec]] are already circling the same model.

## Gate

The three lines above matching CPython, `test_nilpy_none_str_field.npy` extended
with the "" case it currently documents as NOT asserted, plus the per-fix loop.

## Measured 2026-08-09 — the failure is NOT uniform, and that decides the fix

The conflation is exactly **static `AnsiString` vs `Variant`**:

| operand | `"" is None` | correct? |
| --- | --- | --- |
| `x = ""`, `"" + ""`, `"ab"[0:0]`, a `-> str` result, a class FIELD | True | no |
| **`["", "x"][0]`, `{"k": ""}["k"]`** | **False** | **yes** |
| `None is None` / `"abc" is None` | True / False | yes |

A string boxed in a variant carries `VT_STRING` in its TAG and `is None` tests
the tag, so **the variant representation already models None-vs-empty
correctly** — it is only the statically str-typed path, where `pystr_is_none`
tests `Pointer(s) = nil` against an empty AnsiString that IS nil, that
conflates.

That is the useful fact this ticket was missing: "the sentinel needs a
representation `""` cannot collide with" is not a design to invent. One exists
in-tree, works, and is exercised by the corpus. It makes "route str Optionals
through variants" the option with a demonstrated precedent rather than one of
three guesses.

Also measured: `x == ""` answers True correctly, so it is `is None`
specifically that conflates — which gives any fix a ready-made oracle, the
`is`/`==` pair disagreeing the way CPython makes them disagree.

Filed as [[decide-nilpy-none-str-representation]] with the four options and a
recommendation (route `Optional[str]` through variants, and decide the promotion
boundary EXPLICITLY — that boundary, not the representation, is where this will
go wrong; widening a str to a variant from a different direction is what broke
`test_nilpy_none_str_field` earlier the same day).
