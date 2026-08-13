---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`mk()[0].n` answers 7 for EVERY field — including a str field — where CPython answers 3. 7 is VT_OBJECT, the variant's TAG word: the attribute read off a subscript of a CALL RESULT yields the receiver's tag instead of reading the attribute. Binding the element to a name first is correct, and so is `[B(8)][0].n` on a literal list"
status: done
owner: claude-A-C-N
---

# An attribute off a subscript of a call result yields the variant TAG

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-13, differential sweep against CPython.
- **Pre-existing:** identical on `stable_linux_amd64/default/pinned`.

```python
class B:
    def __init__(self, n):
        self.n = n
        self.m = "s"

def mk():
    return [B(3), B(1)]

print(mk()[0].n)     # pxx 7      CPython 3
print(mk()[0].m)     # pxx 7      CPython 's'
e = mk()[0]
print(e.n, e.m)      # pxx 3 s    CPython 3 s   — correct
```

**7 is the answer for every field, whatever its type**, which is what names the
cause: `VT_OBJECT` is tag 7, so the expression is yielding the receiver
variant's first word — its TAG — rather than performing an attribute read at
all.

## The boundary — measured

| expression | pxx | CPython |
| --- | --- | --- |
| `mk()[0].n` (call → subscript → attr) | **7** | 3 |
| `mk()[1].n` | **7** | 1 |
| `mk()[0].m` (a str field) | **7** | `'s'` |
| `d["k"][0].n` (dict → subscript → attr) | **7** | 7 — right by accident |
| `list(reversed([B(4), B(5)]))[0].n` | **7** | 5 |
| `[B(8)][0].n` (a LITERAL list) | 8 | 8 |
| `e = mk()[0]; e.n` | 3 | 3 |
| `xs = mk(); xs[0].n` | 3 | 3 |
| `mk()[0]` printed as an object | correct | correct |
| `type(mk()[0]).__name__` | `B` | `B` |
| `one().n` where `one()` returns a B | 5 | 5 |

So the subscript itself is right (the element prints, and its TYPE is right),
one call-result attribute is right, and only the CHAIN
call → subscript → attribute is wrong. The `d["k"][0].n` row is the dangerous
one: it happens to be right for the value 7 and would be wrong for any other.

## Where to look

The chained-selector path (`PyParseClassRecordSelectors` in pyparser.inc, the
NilPy copy). A subscript of a call result yields a VARIANT element; the
attribute after it must go through `pydynattr_get_v` (which works — the
bound-name rows prove it), and instead something is reading the variant slot's
first word. Suspect the static type carried out of the subscript: if the element
node is typed tyClass with a rec, the `.field` becomes an AN_FIELD at a computed
offset over a variant SLOT rather than over the object it holds.

Same family as [[project_nilpy_lvalue_vs_selector_path_must_both_know]] — member
access by RECEIVER SHAPE, where a bare name and a call result take different
parsers.

## Gate

A `.npy` diffed against CPython: every row of the table above, an int field, a
str field, a float field, a nested call (`mk()[0].inner.n`), a method call after
the subscript (`mk()[0].describe()`), and the bound-name controls kept in the
file.

## 2026-08-13 — measured further, NOT started; here is where the read is NOT built

Probed rather than reasoned, and the useful part is what has been RULED OUT.
No code changed; the tree is back at HEAD.

**Confirmed facts (all on HEAD, all reproduced on the pin):**

  * every field answers **7** whatever its type, and 7 is `VT_OBJECT` — so the
    expression is yielding the receiver variant's TAG word, not reading a field;
  * `(mk())[0].n` — the SAME expression parenthesised — is **correct**. That is
    the sharpest control in the ticket: the parenthesised factor re-enters
    through a different postfix path, so the bug is in the un-parenthesised
    call-suffix chain, not in the subscript or the attribute read themselves;
  * `mk()`'s inferred return type is right (`PXXDBG=n.ret`: tyClass, rec 40 =
    TPyList), so this is not the return-typing family.

**Three candidate paths are ruled OUT by instrumentation** (a `PxxDbgEnabled`
print at each; none fires for this expression):

  * `PyVariantFieldArm` / `PyMakeVariantField` (pyparser.inc) — the
    unbox-cast-read arm a variant receiver normally takes;
  * `PyMakeDynAttrGet` — the dynamic-attribute route;
  * parser.inc's postfix `.`-suffix site (the one that sets `fieldName` at
    ~5524). It fires exactly twice for this program, both for `self.n` inside
    `__init__`, and never for `mk()[0].n`.

So a FOURTH path builds this read. The next thing to probe is pyparser.inc's
`PyParseClassRecordSelectors` (the NilPy copy of the selector loop, split out
2026-08-09) and the subscript-suffix loop in parser.inc that precedes it —
the arm to look for is one that keeps the ELEMENT's static class while the
runtime value is a variant, because that combination is exactly what reads
offset 0 of the slot and answers the tag.

Adding a bare-attribute arm to the subscript-suffix loop and forcing the
receiver through `PyEvalOnce` were both tried and BOTH ARE NO-OPS for this
expression — further evidence that the chain never reaches that loop.

Left claim-free with the measurement so the next session starts from the
ruled-out list rather than re-deriving it.


## FIXED 2026-08-13 — the fourth path was the selector loop's MISSING arm

The previous session's ruled-out list was right and did the hard part: three
candidate paths eliminated, and the note that "a FOURTH path builds this read"
pointed straight at `PyParseClassRecordSelectors`. It is that loop, and what was
wrong with it is an ABSENCE, which is why probes placed on builders never fired
— there was no builder to instrument.

### The measurement that located it

```
mk()[0].n       -> 7      wrong
mk()[0].get()   -> 3      RIGHT
```

The loop has a variant arm for `.name(` — a METHOD on a variant receiver, which
must dispatch at run time — and its guard requires `Tokens[TokPos + 1]` to be
`(`. A bare attribute has no paren, so it fell through to the class/field path
below, which built an `AN_FIELD` over the variant SLOT: offset 0, the tag word,
7 for VT_OBJECT, for every field regardless of type.

That single asymmetry explains the whole table. The method spelling working is
not a curiosity — it is the proof, because both spellings share the receiver,
the subscript and the class; only the arm differs.

### One row of the table above was wrong, and it mattered

`d["k"][0].n` was recorded as "7 — right by accident". It is not a coincidence
row at all: it was measured through a NAME receiver, and a name never enters
this loop (`PyEvalOnce` and the loop are reached for an `AN_CALL` base). Through
a call it is wrong like everything else:

```
d = mkd(); d["k"].n   -> 42   correct
mkd()["k"].n          -> 7    wrong
```

So the rule is **call-result receiver**, not list-vs-dict — which also explains
the `xs = mk(); xs[0].n` and `(mk())[0].n` control rows without needing them to
be special.

### The fix

A sibling arm for the bare attribute, routed through **`PyMakeAttrLoad`** — the
shared builder that keeps the static-field path when the receiver has a known
class and falls back to `pydynattr_get_v` for a variant. Reusing it is the point:
this adds an arm, not a lowering, so there is no second copy of attribute access
to keep in sync (the failure mode
[[project_nilpy_lvalue_vs_selector_path_must_both_know]] warns about).

Assignment targets are deliberately excluded from the arm: a store through this
chain does not parse today at all, which is loud rather than silent, and is
filed on its own as
[[bug-nilpy-assigning-to-an-attribute-of-a-list-element-does-not-parse]].

### Verified

`test/test_nilpy_attr_off_subscript_of_call_result.npy`, expectations generated
by CPython, wired into `test-nilpy`: int / str / float fields, the second
element, a nested attribute (`mk()[0].inner.n`), a method after the subscript,
the dict-through-a-call row, a `reversed()` chain, and six controls that always
worked (bound element, bound expression, parenthesised, list literal, dict
through a name, plain call attribute).

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
