---
prio: 45
track: N
summary: "`from M import X as Y, X2 as Y2` -- the SOURCE name is resolved through flat unit scope, so an earlier alias in the SAME import shadows the next one's source. Cause CONFIRMED 2026-09-10 against `ca814b0aabcc`; SEVERITY CLAIM IS STALE and the prio moved 55 -> 45 because of it. Filed as a silent wrong value; it is now a compile error (`undefined variable (C)`), which is a different thing to rank. Only the colliding pair fails -- two aliases without a collision, one alias plus one plain, two plain and a single alias all answer correctly."
---

# bug: a from-import alias resolves its SOURCE name through flat unit scope, not through the exporting module

- **Type:** bug (silent wrong value — code compiles and runs, and prints the
  wrong thing with no diagnostic).
- **Found:** 2026-08-29, while fixing
  `regression-test-nilpy-test-nilpy-relative-import-in-package`. Not caused by
  that fix — measured identical on a same-base control compiler built without
  it.

## What is wrong

`from M import X as Y` must bind `Y` to **M's** `X`. NilPy resolves `X` with
`FindSym`, i.e. through flat unit scope, so as soon as a name equal to `X`
exists in the importing module — very often one an *earlier alias in the same
import* just created — the source resolves to that name instead of to M's
member. The result is a wrong value, never an error.

## Measured

Three shapes, all against CPython as the oracle. `m.py` is
`A = 5 / B = 18` for the value rows and `def f(): return 5 / def g(): return 18`
for the function rows.

| source | pxx | CPython |
| --- | --- | --- |
| `from m import A as B, B as A` → `A*1000+B` | **5005** | 18005 |
| `from m import f as g` then `print(g(0))`, where `m` also defines `g` | **m.g** | m.f |
| `from m import f as g` / `from m import g as f` (two statements) → `f()*1000+g()` | **18018** | 18005 |

Row 1 and row 3 are the same defect seen from two sides; row 2 is it with no
swap involved at all, and is the smallest repro.

Row 2 is NOT covered by `test_nilpy_from_import_as_alias.npy`, which is the
test that looks like it would catch this: every alias there renames a member
onto a name the source module does **not** also define, so the flat-scope
lookup happens to land on the right symbol.

## Where

`compiler/pyparser.inc`, in `PyParseImportRun`. The lookup:

```pascal
              { FindSym, not PyProgSym: the name belongs to the EXPORTING unit
                and PyProgSym deliberately hides other units' symbols. Flat unit
                scope is what makes the un-aliased spelling resolve, and this is
                the same lookup. }
              aliasRealSym := FindSym(impReal);
```

`FindSym` is flat and has no notion of *which* unit the name should come from,
which is the whole defect. The guard immediately below it:

```pascal
              if aliasRealSym >= 0 then
                for aliasSelfIdx := 0 to PyImpAliasCount - 1 do
                  if (PyImpAliasStmt[aliasSelfIdx] = aliasStmtTok)
                     and (PyImpAliasSym[aliasSelfIdx] = aliasRealSym) then
                  begin
                    aliasRealSym := -1;
                    Break;
                  end;
```

is a patch over exactly one instance of it — the case where the shadowing name
was queued by the same statement. It cannot help row 2, where the shadowing
name is a genuine member of the source module and was never queued at all.

## Direction (not yet chosen — this is the analysis, not a decision)

The shape that matches the language is two-phase per statement: collect every
`(alias, real)` pair of one from-import, resolve **all** the `real` names
against the exporting unit, and only then allocate and bind the aliases. That
is what "CPython binds every name in one from-import from the source module,
simultaneously" means operationally, and it would delete the self-capture scan
rather than extend it.

The obvious cheap version is already known not to work, and the reason is
recorded in the comment above the guard: `from pkgprobe.sub import greet`
resolves through a shim (`pkgprobe_sub -> mimic_pkgprobe_sub`), so a lookup
scoped by unit **name** binds `greet` to None. Any fix has to resolve against
the unit index `PyParseImportUnit` actually pulled, not against the spelling in
the source.

## Why prio 55 and not higher

Every row is a wrong value rather than a failure to compile, but all three need
a module that defines a name an alias also mentions — real packages do this
when they re-export, which is why it is not lower.

# Re-measured 2026-09-10, frankB, compiler `ca814b0aabcc`

**THE CAUSE IS CONFIRMED AND THE SEVERITY CLAIM IS STALE — and this ticket is
ranked partly on the severity claim.** It is filed as a *silent wrong value*
("code compiles and runs, and prints the wrong thing with no diagnostic"). It no
longer does that. Today the same source is a compile error:

```
from srcmod import A as B, B as C     # srcmod: A="srcmod-A", B="srcmod-B"
print(B); print(C)
-> pascal26:5: error: undefined variable (C)
```

CPython prints `srcmod-A` / `srcmod-B`. So we still get it wrong; we now get it
LOUDLY wrong, which is a different ticket to rank.

## The collision is the whole variable — alias-count and collision varied separately

| shape | result |
| --- | --- |
| `from srcmod import A as X, B as Y` (two aliases, no collision) | correct |
| `from srcmod import A as B, B as C` (two aliases, collision) | **error** |
| `from srcmod import A as X, B` (one alias, one plain) | correct |
| `from srcmod import A, B` (no alias) | correct |
| `from srcmod import A as X` (single alias) | correct |

Four negative shapes, one positive. That confirms the mechanism the ticket
names — the source name is resolved through flat scope, so an earlier alias in
the same import statement shadows the next one's SOURCE — while showing the
observable has moved.

## Why this is worth recording rather than just re-ranking

A ticket's DIAGNOSIS can stay true while the thing it is RANKED on moves
underneath it, and nothing re-reads a prio when a neighbouring fix changes an
observable. This one decayed in the SAFE direction (wrong value -> refusal), so
it is merely over-ranked. The mirror — a ticket filed as a refusal that quietly
becomes a wrong value — is under-ranked, therefore never picked up, therefore
never re-probed, and is invisible for exactly the reason it is dangerous.

Prediction, stated as one and not as a measurement: severity decay accumulates
hardest in whatever sits longest, because sitting is what prevents the re-probe.
A ticket that has quietly become a silent wrong value ends up filed where the
ranker never scans.

The cheap remedy is not "re-probe the backlog". It is: **when you fix something,
re-probe the neighbours that share its OBSERVABLE, not only the ones that share
its cause.** Shared cause is what a working group is organised around; shared
observable is a different neighbourhood, and it is the one severity decay
travels through.
