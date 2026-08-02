---
track: N
prio: 60
type: bug
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
