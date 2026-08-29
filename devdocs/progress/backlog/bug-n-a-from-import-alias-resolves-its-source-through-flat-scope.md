---
prio: 55
track: N
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
