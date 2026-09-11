---
prio: 60
track: N
summary: "`from M import X as Y` resolves the SOURCE name X through flat unit scope instead of through M, so any equal name in flat scope wins. TWO SEVERITIES, ONE CAUSE: a collision INSIDE one import statement is now a compile error (`undefined variable`), but two DIFFERENT modules each exporting the same member name is still a SILENT WRONG VALUE -- both aliases answer the later module (measured 2026-09-11, `8b0839edde8f`). Prio 45 -> 60 on the silent arm, which the 2026-09-10 re-measure concluded had gone and had not varied the module axis."
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

# Re-measured 2026-09-11, frankZ, compiler `8b0839edde8f` — THE SILENT ARM IS NOT GONE, AND THIS TICKET PREDICTED ITS OWN BLIND SPOT

**The severity claim above is stale in the direction the section below it calls
the dangerous one.** The 2026-09-10 re-measure found the observable had moved
from a wrong value to `undefined variable (C)`, and this ticket was re-ranked
55 → 45 on that. There is a shape where it is **still silent**, and it is not an
exotic one:

```python
# a/__init__.py:  WHO = "fallback"
# b/__init__.py:  WHO = "selected"
from a import WHO as A
from b import WHO as B
print(A, B)
```

| | |
| --- | --- |
| CPython | `fallback selected` |
| pxx | **`selected selected`** |

Exit 0, no diagnostic. Both aliases answer the LATER module's member.

## Why the 09-10 table could not see it, and the distinction is the finding

Every row of that table varies **alias count and collision within ONE import
statement**, against ONE source module. The variable this shape moves is a
different one: **two source MODULES that each declare the same member name**,
one alias per statement, no collision inside either statement. The 09-10 row
*"two aliases, no collision — correct"* is true and does not cover it.

It is the same cause the ticket names, with nothing added: `FindSym(impReal)` is
flat, so `WHO` resolves to whichever `WHO` is in flat scope rather than to the
one belonging to the unit `PyParseImportUnit` just pulled. The within-statement
self-capture scan is irrelevant here — neither name was queued by the other's
statement — which is why the guard cannot reach it and why the observable stays
a value instead of becoming a refusal.

**So the cause is single and the SEVERITY is two-valued**, depending on whether
the shadowing name comes from the importer's own statement (loud) or from
another module's export (silent). A ranking argument that reads only the loud
half under-ranks the ticket.

## Prio 45 → 60

Not for the mechanism, which is unchanged and was correctly diagnosed a fortnight
ago, but because the silent arm is alive and the population is ordinary: any two
modules sharing a member name — `NAME`, `VERSION`, `WHO`, `main`, `parse`,
`Error` — collide the moment both are aliased. Re-exporting packages are the
named population above; this needs no re-export at all.

## How it was found, which is worth more than the row

Writing a fixture for an unrelated bug (`try/except/else` with an import in the
try body). Its two arm modules each declared a constant, and I named both `NAME`
**on purpose, to sharpen the differential** — one module answers "fallback", the
other "selected", so any arm confusion shows up in one word. That naming is what
created this collision, and the fixture duly reported the handler arm returning
the else arm's value: a real defect, wearing the costume of the bug under test,
in the row that was supposed to be the discriminator.

**A fixture's own naming choices are inside the population it measures.** The
house rule about a measurement creating the condition it tests for is written
about a run's earlier STEPS supplying what a later one needs; this is the same
shape one level earlier, in the fixture's DATA. The tell was that the control
row moved too. The remedy was to name the two constants differently and let the
MODULE, not the member, carry the identity — and then the arm bug reproduced on
its own, at which point this one had to be split out rather than fixed in
passing.

Section above, on re-probing the neighbours that share an OBSERVABLE: this is an
instance, and the observable moved twice — silent, then loud, then silent again
in a shape nobody had varied.
