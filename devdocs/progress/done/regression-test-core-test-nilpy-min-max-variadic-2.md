---
prio: 70
track: N
status: done
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 10 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_min_max_variadic.npy red at 1d98cf21375f (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-29T16:55:03Z
- **Test source:** test/test_nilpy_min_max_variadic.npy tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_min_max_variadic.npy'` at 1d98cf21375ff1166329c5568643600aa63ece72

## Range
> **The named sha `1d98cf21375f` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `1d98cf21375f`, last good `154d1aa3fba6`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:8: error: Nil Python: no 2-argument ( for these operand types
(tail)
pascal26:8: error: Nil Python: no 2-argument ( for these operand types
  near:  max     >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Root cause — an aliased `const` parameter, not a type-dispatch failure

`PyParseVariadicMinMax(const nm: AnsiString)` is called as
`PyParseVariadicMinMax(CurTok.SVal)`. A `const` AnsiString parameter binds
**by reference**, so `nm` was never a copy — it was the live token text. The
function's first act is `Next`, which does `SetLength(CurTok.SVal, ...)` **in
place** (that hazard is written up in `PyEvalParamDefault`). So the fold asked
`MatchProcCall(nm, 2, ...)` for a routine named **`(`**, which does not exist.

The error text said so all along: *"no 2-argument **(** for these operand
types"* prints `nm`. Reading `(` as punctuation in the message rather than as
the interpolated value is what made this look like a dispatch problem.

That also explains the shape of the failure — int, float, str and mixed
literals fail **identically**, because the name is wrong before the operand
types are ever consulted.

### Why the boundary sat exactly at 5

The gate in `pasparser_expr.inc` only enters the fold when no routine of that
arity exists. pylib has hand-written 3- and 4-argument all-Variant overloads,
so 2/3/4 never reached the broken code. 5 was the first arity with no
hand-written overload — i.e. the first that reached the fold at all.

| args | 2 | 3 | 4 | 5 | 6 | 9 | 12 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| before | ok | ok | ok | **error** | **error** | **error** | **error** |
| after | ok | ok | ok | ok | ok | ok | ok |

All values match CPython, for int, float, str and mixed operands.

## Fix

Copy the characters into a local before advancing — the idiom every other arm
in `pyparser.inc` already uses (`nm := CurTok.SVal`). `ParseGenericTemplateNamed`
carries **this same fix with this same comment**, so the hazard had been
diagnosed once before and this call site was the sibling that was missed.

## Sibling sweep

Every `const`-parameter callee invoked with `CurTok.SVal` that then advances
the cursor (52 callees examined; 3 advance):

- `ParseGenericTemplateNamed` — already copies, with the explanatory comment.
- `PyParseImportUnitAs` -> `ParseUsesUnit` -> `ParseUsesUnitBody` — forwards the
  alias down three frames, but `ParseUsesUnitBody` consumes it into `lo` /
  `cName` / `gPath` before its first `Next`. Safe.
- `PyParseVariadicMinMax` — this ticket. The only live instance.

## Not established: which commit made it observable

The call site has passed `CurTok.SVal` since the feature landed (`aaf5c89a3`),
and `9768baf44` only moved the line between files — so the **alias predates the
watcher's 4-commit range** and was latent. The only compiler changes in that
range are `0d91dc88f` (release owned string operands of a comparison, x86-64)
and a `symtab.inc` change. **I did not bisect to confirm which exposed it**, and
it does not change the fix: the alias is the defect and both of those changes
are correct.

Flagging it for Track A anyway, since `0d91dc88f` touches string ownership: if
it did expose this, other latent aliases could have gone live with it. The
token-text shape is swept above and clean.

## Note for the earlier instance

`regression-test-core-test-nilpy-min-max-variadic` (the `-1`) was a **different
defect** — a def-shell visible above its own `def` statement. Unrelated
mechanism; the shared test name is the only connection.

## Log
- 2026-08-29 — root-caused, fixed, sibling-swept; resolved.
- 2026-08-29 — resolved, commit PENDING-COMMIT.
