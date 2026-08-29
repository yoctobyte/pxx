---
track: P
prio: 35
type: bug
status: backlog
blocked-by: []
owner: ""
summary: "ParseFactorCore's carve-out to PyParseFactorCore is partial: 36 NilPy diagnostics remain on the Pascal arm and 10 exist verbatim on BOTH arms, so a correction to one of them lands on one arm and silently leaves the other stale."
---

# Ten NilPy diagnostics exist on both arms of the ParseFactorCore carve-out

- **Type:** bug (maintenance hazard, not a wrong answer today) — **Track P**
  file-ownership (`compiler/pasparser_expr.inc`), touching **Track N**
  (`compiler/pyparser.inc`). One agent holding P+N can do both; otherwise it is
  a P change plus an N change.
- **Found:** 2026-08-29, by the coordinator, while correcting a stale quoted
  diagnostic in `devdocs/dev/nilpy-semantics-divergences.md` for frankD.

## What is actually there

The carve-out is deliberate and documented — `compiler/pyforwards.inc:37`:

> `procedure PyParseFactorCore; forward;  { the NilPy half of ParseFactorCore, carved out into pyparser.inc — ParseFactorCore dispatches here on PyExprMode }`

**It is partial.** Measured at `d6cd7ebb9`:

| | `Nil Python:` diagnostics |
| --- | --- |
| `compiler/pyparser.inc` | 505 occurrences, 312 distinct |
| `compiler/pasparser_expr.inc` | 37 occurrences, 36 distinct |
| **present verbatim in BOTH** | **10** |

The ten:

```
Nil Python: exec(src) with no namespace is not supported — …
Nil Python: expected method after super().
Nil Python: getattr on an attribute this type does not declare needs a default
Nil Python: len() could not call __len__
Nil Python: promocore (PXXPromoToBase) not loaded
Nil Python: promocore (PXXPromoToStr) not loaded
Nil Python: pyeval (EvalPyStmts) not loaded
Nil Python: pyeval (pyeval_expr) not loaded
Nil Python: pyfilter_iter_i / pymap_iter_i not loaded
```

The `exec` one is byte-identical across `pyparser.inc:44129` and
`pasparser_expr.inc:2615` — the same six-line `Error('…')` construction,
including the doubled quote in `caller''s`.

## Why it is worth a ticket rather than a shrug

This is the shape `devdocs/dev/normalise-dont-special-case.md` names — *if you
fix a bug on one arm of a double case, grep for the sibling before closing the
ticket* — and the double arm here is **invisible from either side**. Someone
improving the `exec` refusal reads one file, sees one definition, and has no
signal that a second copy exists. The failure mode is not a wrong answer, it is
a correction that lands at 50% and reports success.

It has a live consumer: `docs/targets/nil-python.md` (frankD, `ca3815d74`)
QUOTES the exec refusal on the public website, and
`devdocs/dev/nilpy-semantics-divergences.md` quotes it too. A future edit to
whichever arm the author happens to open can leave the published page quoting
the other. The doc quote had *already* rotted once — it was missing the whole
final clause until `d6cd7ebb9` — and that was against a single arm.

## What is NOT claimed here

- **Not** that the carve-out was wrong. Duplicating a parser *across* languages
  is the deliberate rule
  (`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md`): share the AST
  and the IR, duplicate the parser. This ticket is about the ten places where
  the duplication is *within* the split rather than across it.
- **Not** that either arm is dead. Nobody has measured which arm a `.npy`
  compile actually reaches for these ten, and reasoning about the `PyExprMode`
  dispatch is not measurement. **Do that first** — the answer changes the fix.
- **Not** that all 36 residual strings should move. Several are `… not loaded`
  runtime-library guards, which may legitimately belong on both arms.

## Work

1. **Measure, do not reason.** For each of the ten, determine which arm a
   NilPy compile reaches — `PXXDBG` or a deliberate divergence in one copy's
   text, then compile a `.npy` that triggers it and read which text appears.
2. Dead arm → delete it. Live on both → hoist the string to one shared
   constant so the two arms cannot drift, which is the normalise-don't-
   special-case answer and is cheaper than keeping them in sync by discipline.
3. Leave the `… not loaded` guards alone unless step 1 says otherwise.

Gate is the owning lane's ordinary one; per CLAUDE.md that is
`make compiler/pascal26` plus the repro, and breadth is Track T's.
