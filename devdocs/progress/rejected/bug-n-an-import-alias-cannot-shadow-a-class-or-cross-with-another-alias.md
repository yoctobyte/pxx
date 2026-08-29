---
track: N
prio: 60
type: bug
blocked-by: []
summary: "Two rows of the alias table that the proc-rebinding fix does NOT reach, because each is a different mechanism. (1) `from M import f as C` where M also has a CLASS named C still CONSTRUCTS M's C — the fix stamps the proc chain, and a class is not on it; FindUClass scans the real class table before the alias table, so there is no way to say `C is not a class here`. (2) `from M import f as g, g as f` answers `5 5` where CPython answers `5 18` — crossing aliases must both read the PRE-import bindings, and the second binding sees the first. Both were rows of the parent ticket; split out because neither is a variation of the proc arm."
status: rejected
owner: ""
---

# An import alias cannot shadow a class, and two aliases cannot cross

- **Type:** bug (name binding) — **Track N** (Nil-Python frontend).
- **Split from** [[bug-n-an-import-alias-binds-to-a-same-named-member-of-the-source-module]]
  on 2026-08-29 by frankA, when the proc arm of that ticket landed. These are
  the two rows of its table the fix does not reach.
- **Measured at** the fix's own build, differential against CPython on the same
  file.

## Row 1 — the alias name is a CLASS in the source module

```python
# mmod.py
def f(a, lo=7):        return lo
class C:
    def m(self, a, lo=7): return lo
```
```python
from mmod import f as C
print(C(1, 5))     # CPython 5   —   pxx: <__main__.C object at 0x…>
```

**pxx constructs `mmod.C` instead of calling `f`.** The parent ticket called
this "the worst shape" and it is: nothing about the output says a call was
replaced by a construction.

### Why the proc fix does not reach it

That fix stamps `ProcPyAliasRebindTok` for every entry on the PROC chain named
by the alias, and `PyDefRebound` reads the stamp. **A class is not on the proc
chain.** The class arm of the alias code is a separate branch entirely:

```pascal
aliasCi := FindUClass(impReal);            { 'f' is not a class -> -1 }
if (aliasCi >= 0) and (impAlias = impReal) then { nothing to do }
else if aliasCi >= 0 then RegisterUClassAlias(...)
else if PyImpAliasCount < 64 then ...      { the proc/sym arm — where we land }
```

The branch is chosen on whether the **REAL** name is a class. Here it is not —
`f` is a proc — so the class table is never consulted about the **ALIAS** name,
and `C` goes on meaning `mmod.C`.

### Why it is not a one-liner, and this is the real content of the ticket

The obvious fix — "register an alias row mapping `C` to nothing" — **does not
work**, and the reason is worth stating so the next person does not spend the
attempt. `FindUClass` consults the alias table **only after the real class scan
has already failed** (`symtab.inc`, `if Result >= 0 then Exit;` immediately
before the alias loop). A shadowing entry placed there is unreachable by
construction: the genuine `mmod.C` row is found first, every time.

Shadowing therefore needs a **new concept** — "this name does not name a class
in the module being compiled" — tested *before* the class scan. `FindUClass` is
called from a great many sites, so that is a real change with a real blast
radius, not a drive-by. It is the same shape as the fix that did land (a
per-name stamp consulted by the resolver) applied to a resolver that is not
structured to receive it yet.

## Row 2 — two aliases crossing

```python
from mmod import f as g, g as f
print(g(1, 5), f(1, 5))    # CPython "5 18"   —   pxx "5 5"
```

`g` is right; `f` is wrong. Python evaluates **all** the right-hand sides
against the bindings in force *before* the statement, then binds; here the
second alias appears to see the first one's effect, so `f` ends up meaning
`mmod.f` (5) rather than `mmod.g` (18).

Named in the parent ticket's "what to check" list, so it is a known-wanted case
rather than a curiosity. Not investigated beyond confirming the value, because
it is a **simultaneity** question — the order the queued bindings are
materialised in — and not the resolution question the parent ticket was about.
`PyFlushImportAliasesFrom` drains its queue in order and emits `ALIAS = NAME`
assignments; if the RHS of the second reads a name the first has already
rebound, that is the defect, and it would be visible there.

## What is already fixed, so nobody re-tests it

Landed with the parent ticket — do not read this ticket as "aliases are broken":

| shape | now |
| --- | --- |
| `from M import f as g` where M also has `g` | **fixed** |
| `from M import g`, then `g = <local def>` | **fixed** |
| `from M import f, g`, then `g = f` | **fixed** |
| a call ABOVE the import | correctly unaffected |
| fresh alias name, same-file def rebinding, rebinding to a non-callable | were already correct |

## Gate

Track N's: `make compiler/pascal26` (byte-identical self-host fixedpoint) plus a
CPython differential on the two rows above. Add them to
`test/test_nilpy_import_alias_collides.npy`, whose fixture
(`test/nilpy_aliasmod.py`) already exists and would need a class added for row 1.

---

## WITHDRAWN THE SAME DAY IT WAS FILED — both rows were already fixed

**Obsolete on arrival, 2026-08-29 (frankA, its own filer).** Filed while another
agent was fixing this ticket's parent concurrently; neither of us could see the
other. Both rows below were closed by that agent's work, which landed while mine
was in rebase.

Re-measured on the COMBINED tree (both fixes present, self-host fixedpoint
`d1328d1d804b`), against CPython:

| row this ticket filed | result |
| --- | --- |
| `from M import f as C` where M has a class `C` | **5** — matches CPython, no construction |
| `from M import f as g, g as f` | **`5 18`** — matches CPython |

So the analysis in the body is **wrong about the conclusion and right about the
mechanism**: the constructor path really is a second mechanism that the proc
stamp cannot reach, and `FindUClass` really does consult the alias table only
after the real class scan succeeds. The other agent fixed it at
`PyIsExactCtorName` — the constructor decision itself — rather than by teaching
`FindUClass` a shadowing concept, which is why the route I said was needed was
not the route taken. Kept rather than deleted for that reason: the dead end is
accurate and someone will consider it again.

**The coordination lesson is the useful part.** Two agents fixed one ticket in
parallel, and the split fell exactly along file ownership: the other agent left
the one row whose fix lives in `compiler/symtab.inc` (Track A's file, held by
me), and I split out as out-of-reach precisely the rows they had already done.
Neither of us was wrong; neither of us could see the other's tree. Nine rows now
match CPython where the ticket opened with four diverging.
