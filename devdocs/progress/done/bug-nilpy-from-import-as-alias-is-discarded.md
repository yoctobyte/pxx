---
track: N
prio: 60
type: bug
status: done
owner: claude-AN-night
---

# `from mod import NAME as ALIAS` — the alias is parsed and thrown away

- **Type:** bug (NilPy frontend gap — loud) — **Track N**
- **Found:** 2026-08-02, by a differential sweep against the CPython oracle.

## Measured

With a `helper.py` exporting `VALUE = 42`, `def double(x)` and `class Thing`:

| form | result |
| --- | --- |
| `import helper` then `helper.VALUE` | ok |
| `import helper as h` then `h.VALUE` | ok |
| `from helper import VALUE` | ok |
| `from helper import Thing` | ok |
| **`from helper import VALUE as V`** | **`undefined variable (V)`** |
| **`from helper import double as d`** | **`undefined variable (d)`** |
| **`from helper import Thing as W`** | **`undefined variable (W)`** |

So the MODULE alias works and the un-aliased member import works; only the
member ALIAS is broken, and it is broken for every kind of member.

## Cause

In the `from` branch of the import parser (`pyparser.inc`, ~16067) the alias is
consumed and discarded:

```pascal
while CurTok.Kind = tkIdent do
begin
  Next;
  if PyIsIdent('as') then
  begin
    Next;
    if CurTok.Kind = tkIdent then Next;   { <-- alias parsed, never recorded }
  end;
  if not Eat(tkComma) then Break;
end;
```

The `import X as Y` branch immediately below shows the intended shape — it
interns both names and registers a `UnitAliasName`/`UnitAliasReal` pair.

## Why this is NOT a one-liner

There is no general name-alias registry to point at. `from mod import NAME as
ALIAS` has to make ALIAS resolve to whatever NAME is, and that is a different
mechanism per kind:

- **class** — `RegisterUClassAlias` exists (`parser.inc:24486`) and is the
  clean case.
- **function** — needs a proc alias; no equivalent registry.
- **value/const** — needs ALIAS to share NAME's STORAGE, not a copy, or the
  alias silently diverges after a write.

A class-only fix would be safe (the other two stay loud) but leaves the two
commonest spellings broken, so it is worth deciding the general mechanism first
rather than landing a third of it.

**Deliberately not attempted in this session.** Two other "obvious half"
attempts tonight — `def f(a, b=2, *rest)` and the class-attribute lookup — both
turned a loud, correct refusal into a silent wrong value or a crash and were
reverted. This one has the same shape and would want the same scrutiny.

## Gate

A `.npy` diffed against CPython covering `as` on a value, a function and a
class; several aliases in one `from` statement; an alias colliding with an
existing local name; and the un-aliased and module-alias forms as controls.


## Resolved 2026-08-03 — desugared to what Python actually does

The ticket's worry was that there is no general name-alias registry to point
ALIAS at, and that the mechanism differs per kind. Both true; the way out is not
to build a registry.

**`from mod import NAME as ALIAS` is desugared to `ALIAS = NAME`** — a real
binding in the importing module, which is exactly what CPython's import does.
That settles the ticket's third concern by construction: the value/const case
does NOT want shared storage. A later `ALIAS = x` must rebind the alias and
leave the exporting module's name alone, and an assignment gets that right
while a storage-sharing alias would have got it wrong. It is a gate line in the
test for that reason.

The right-hand side is built by the ORDINARY value paths, so a def becomes the
same function object `d = double` builds. `PyMakeFuncValue` was split into
`PyMakeFuncValueFor(pi, name)` plus a thin token-consuming wrapper, so the two
callers share one implementation rather than growing a second that can drift.

A **class** cannot go through an assignment — measured: `W = Thing` then `W()`
yields a pointer with no members, because a class held in a variable is not
constructible in this frontend. Classes take `RegisterUClassAlias` instead, the
same registry a Pascal `TOptionList = TList;` uses, which resolves the alias
onto the same class row for var decls, `ALIAS()`, casts and is/as alike.

### The bug behind the bug — two class-name predicates disagreed

Landing the class half exposed a separate, pre-existing defect, and it was a
SEGFAULT rather than an error:

```python
b = BoxAlias(9); b.get()   # fine
print(BoxAlias(9).get())   # SIGSEGV
```

`FindUClassNonRecord` did not consult the class-alias table; `FindUClass` /
`IsClassType` did. The NilPy construction intercept (`parser.inc`:
`FindUClassNonRecord(...)` and the next token is `(`) therefore stood down for
an alias, and the Pascal **class typecast** branch below it — which asks
`IsClassType` — claimed `BoxAlias(9)` as a hard reinterpret cast of the integer
9 to a class pointer. The first member access dereferenced 9.

`FindUClassNonRecord` now resolves aliases too (skipping one that points at a
record, which is the only thing that function exists to do). This is not
specific to imports: **any** class alias reached from NilPy had it.

Found by dumping the AST (`PXXDBG=a.ast:bad` against a working twin), which
showed node kind 63 = `AN_CLASS_CAST` where the working form had
`AN_CALL(-tkGetMem)`. Reading the two predicates first would have been guessing;
the dump named the branch in one run.

### Deliberately still loud

A `from ... import ... as ...` inside a BLOCK goes through `PyParseOneImport`,
a separate routine that was not touched, so the alias there is still discarded.
Module-level imports are the shape real code uses and the shape the ticket
measured; the in-block form is left as it was rather than half-covered.

A real name that resolves to neither a symbol, a proc nor a class also stays
undefined and walls at its use site — the pre-existing behaviour, and still the
honest one.

### Verified

`test/test_nilpy_from_import_as_alias.npy` (+ `.expected`, wired into
`make test-nilpy`), byte-identical to CPython: `as` on a value, a def and a
class; several aliases in one `from`; inline construction through the class
alias plus a member access AND a field read (the segfault case); the un-aliased
member imports and the module alias as controls; and rebinding the alias,
checking that both the exporting module's qualified name and the un-aliased
import still read the original value.

`gate.sh quick` GREEN, self-host fixedpoint byte-identical, FPC seed clean.

## Log
- 2026-08-03 — resolved.
