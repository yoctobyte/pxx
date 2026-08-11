---
prio: 55
track: N
type: bug
blocked-by: []
---

# `x is None` answers wrong whenever `and` / `or` / `else` follows it

- **Type:** bug (NilPy, silent wrong value on ordinary code) — **Track N**
- **Found:** 2026-08-11, sweeping shapes around
  [[bug-nilpy-name-bound-by-a-method-call-in-a-block-is-undefined-later]].
- **Owner:** —

```python
def f(i):
    if i > 1:
        return None
    return "ok"
b = f(2)                       # b is None
```

| spelling | CPython | pxx |
| --- | --- | --- |
| `b is None` | True | True |
| `if b is None:` | taken | taken |
| `b is None and True` | **True** | **False** |
| `b is None or False` | **True** | **False** |
| `1 if b is None else -1` | **1** | **-1** |
| `if b is None and True:` | **yes** | **no** |
| `xs = [1] if b is None else [2]` | **[1]** | **[2]** |

The last four are ordinary Python. `if x is None and y:` is not an exotic
spelling — it is the commonest compound None guard there is, and it silently
takes the other branch.

## Cause — MEASURED, and it is not the ternary

The first read of this was "the ternary condition is inverted". That was wrong;
the ternary is only the shape it was noticed in. `PXXDBG=a.ast:<proc>` on the
two spellings:

| | the condition node |
| --- | --- |
| `if b is None:` | `kind=8 tk=2` — an **AN_CALL** returning Boolean, argument `b` (tk=23, AnsiString): `pystr_is_none`, which knows a NilPy `None` for a str-typed value is a **nil AnsiString handle**. |
| `1 if b is None else -1` | `kind=5 tk=2` — a generic **AN_BINOP**, left `b` (tk=23), right `kind=8 tk=22`, a CALL returning a **VARIANT**: `PyMakeNone`. |

`PyParseIsCmp` picks the type-aware lowering (a tag test for a variant,
`pystr_is_none` for a string, a compare against 0 for a scalar or pointer) only
when `PyBareNoneHere` says the `None` is bare. Otherwise `None` is parsed as an
ordinary primary — a boxed VT_EMPTY variant — and compared to a managed string
handle with a generic binop that tests nothing relevant.

And `PyBareNoneHere` is an **ALLOW-LIST of what may follow `None`**:

```pascal
PyBareNoneHere := Tokens[TokPos].Kind in
  [tkNewline, tkDedent, tkIndent, tkEOF, tkComma, tkRParen, tkRBrack,
   tkEnd, tkColon, tkSemicolon];
```

`tkAnd`, `tkOr` and `tkElse` are simply not in it. That is the whole bug, and it
is the [[project_nilpy_class_attribute_lowering_matrix]] shape again: a list of
accepted token contexts beside a real expression path, silently disagreeing at
every context nobody thought to list.

## The fix is a SECOND question, not a wider allow-list

The obvious move — add `tkAnd, tkOr, tkElse` to `PyBareNoneHere` — is wrong,
and checking the other call sites is what shows why. **`PyBareNoneHere` has NINE
call sites**, and at eight of them the follow set is load-bearing as *"this
`None` is the WHOLE expression"*: they consume the token and build `PyMakeNone`
without parsing further, so `res = None or 5` would swallow the `None` and leave
`or 5` dangling. The list is not a sloppy allow-list there; it is the test those
sites need.

The `is`-compare site (line ~2037) is asking a **different question**. After
`is` / `is not`, a `None` is the comparison's right operand no matter what
follows — the outer `PyParseBoolAnd` / ternary handles the rest — so what it
wants is simply "is the current token `None`", i.e. `CurTok.Kind = tkNil`.

So: give the `is` site its own predicate (`PyNoneOperandHere`) rather than
touching the shared one. One call site changes, all seven rows above are fixed
by it, and the eight value sites keep the semantics they actually rely on. The
family sweep is still mandatory — `is None` is everywhere in the corpus.

## Gate
The seven rows above matching CPython byte for byte; the same table with an
**int**-returning def (it is not str-specific — `h is not None` on an
`Optional[int]` is wrong the same way, which rules out the nil-handle
representation as the cause); `while` / comprehension-filter / `assert`
spellings; `make compiler/pascal26` + `tools/gate.sh quick`; and
**`make test-nilpy`** as the family sweep, which the nine call sites make
mandatory.

## Not new
Reproduces identically on the v257 pinned binary and on HEAD. Nothing in the
2026-08-11 session caused it; the position has simply never been asked.
