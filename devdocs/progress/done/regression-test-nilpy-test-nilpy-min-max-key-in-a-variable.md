---
prio: 70
track: N
status: done
owner: frankA
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 47 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_min_max_key_in_a_variable.npy red at 0200df7eabcd (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T02:33:24Z
- **Test source:** test/test_nilpy_min_max_key_in_a_variable.npy test/test_nilpy_min_max_key_in_a_variable.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_min_max_key_in_a_variable.npy'` at 0200df7eabcd33796c0f7ac151b80aafbf75b5fb

## Range
> **The named sha `0200df7eabcd` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0200df7eabcd`, last good `3f854c927aac`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3750893/test_nilpy_minmaxkey26  [code=1266131B  data=56251B  bss=51796B  procs=1866]
Unhandled exception: TypeError: expected a number, got object
--- test/test_nilpy_min_max_key_in_a_variable.expected	2026-08-29 16:03:42.852941360 +0000
+++ -	2026-08-30 02:07:27.040169760 +0000
@@ -4,8 +4,3 @@
 var-lambda 3 1
 bound 3 1
 inline-bound 3 1
-variant-container 3 1
-sorted [3, 2, 1]
-plain 1 3 1 3 1.5
-strings a b
-bylen a ccc

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-08-30 — triaged (frankB). Reproduces at HEAD. Same cause as the key-none regression.

**Track N is correct** — the guess in the header holds. The code is
`compiler/builtin/pylib.pas` + `compiler/pyparser.inc`, not `lib/**`, so this is
not Track B's despite the runtime-looking symptom.

### Reproduces at the current pin

v394 `53800fbeb0b66e11`. Both regressions still fail, so this is not one of the
"already fixed by something else" cases the header warns about.

### The boundary — it is the RECEIVER, not the key

Minimal repro, three lines:

```python
def f(xs, key=None):
    return min(xs, key=key)
print(f([5, 2, 9]))          # CPython: 2      pxx: TypeError: expected a number, got object
```

The full matrix (`min(xs, key=K)`; CPython gives 9 for the callable keys, 2 for
`None`):

| receiver | `key=lambda x: -x` | `key=pk` (def name) | `key=f` (variable) | `key=None` |
| --- | --- | --- | --- | --- |
| module-level `xs = [5,2,9]` | 9 | 9 | 9 | 2 |
| **function parameter `xs`** | 9 | **TypeError** | **TypeError** | **TypeError** |

Every module-level row passes. Three of four function-parameter rows fail, and
only the **inline lambda** survives.

So the discriminator is **a variant receiver combined with a key that is not an
inline-lambda (pointer-typed) node**. It is not about `None`, and it is not about
being inside a function: `key=0` fails identically, and a literal list inside a
function works. The earlier ticket
[[bug-nilpy-min-max-with-a-key-held-in-a-variable-picks-the-numeric-overload]]
fixed exactly this family for the **static-list** receiver — its own table's
rows all pass today — and the **variant-container** arm is the half that is red.
That ticket's fix note names both shapes explicitly ("a static list boxed on the
way in, and a variant container") as the two that `PyMinMaxByKey` was made the
single meeting point for, which is why one arm regressing is the expected shape
of a break here rather than a surprising one.

### Same cause as `regression-test-nilpy-test-nilpy-min-max-key-none`

Not merely the same exception string. Both need the same two conditions, and
each ticket is one column of the table above: `key-none` is the `key=None`
column, this one is the `key=f` column. `min([3,1], key=None)` at module level
still prints `1` — which is why the `key-none` test's first two lines pass and it
dies at the first row that routes through a function. **One fix, one gate.**

### Candidate cause — NOT a confirmed bisect

Exactly one commit in the watcher's 6-commit range touches either file:

> `7b73a385d feat(N): list.sort(key=) — and the callable→Pointer coercion every
> method loop was missing`

It refactors the callable→Pointer coercion into `PyCoerceCallableArgsIn`, applies
it in the method-call loop, and adds `pyvar_callable_ptr_opt` for the `key=None`
spelling — i.e. it edits precisely the mechanism the earlier fix rests on.

**This is circumstantial and is deliberately not recorded as the cause.**
Confirming it means building at `7b73a385d~1` and at `7b73a385d` and running the
matrix, which is a compiler rebuild and therefore Track A/N work, not Track B's.
The named sha `0200df7eabcd` remains impossible as a cause (it touches no
buildable file); this is a better candidate, not a verdict. Whoever takes it
should run the two builds before writing a cause into this ticket — a plausible
attribution nobody diffed is the failure this repo has recorded most often.

### Gate

The matrix above for `min` and `max`, both receiver shapes × all four key
spellings, plus `sorted` with the same keys as the control (its overloads are all
`key: Pointer`, so it has no competing numeric candidate and should stay green
throughout). The two existing `.npy` tests already cover most of it; add the
variant-receiver rows for `key=None`, which is the column neither test exercises
outside a helper.

---

## Resolved — the `Variant` keyed receiver was missing from the `min`/`max` set

**Cause, by diff and not by adjacency.** Built both sides of the suspect commit
with per-commit reseeding (each from its own `stable_pinned`, `converged after`
required in the log before any verdict was accepted):

```
7b73a385d^ (30f18eb55)   all 8 rows pass
7b73a385d                module rows pass, then: TypeError: expected a number, got object
```

`7b73a385d` moved the callable->Pointer coercion into `PyBindKwArgs`. After it, a
receiver whose static type is `Variant` — which is what a **function parameter**
holding a list is — had no keyed overload to bind to, so the call fell through to
the two-argument scalar form and compared the list against the key.

**Fix:** `compiler/builtin/pyeval.pas` grows the `Variant` keyed pair, completing
the receiver set `sorted` already had (TPyList / TPyDict / AnsiString / Variant /
TPyIter / TPyRange). Both arms dispatch on `pyvartag`: 7 -> `pyseq_of_obj`,
6 -> `pystr_of`, else raise. `key: Pointer = nil` — the **default matters**, it is
what lets `key=None` reach the same arm instead of degrading.

**Why this arm was removed once and had to come back.** An earlier measurement in
this session concluded the Variant pair "buys nothing". That measurement was
**vacuous**: it used only module-level *literal* receivers, which are never
variant-typed, so the population could not contain the case the overload serves.
Re-measured against a function parameter — the true-variant receiver — it is the
whole fix. See `a-zero-can-be-vacuous-check-the-population`.

**Verified** (`pyeval.pas` is consumed when compiling a `.npy`, not linked into
the compiler, so each A/B is a recompile of the test only — no rebuild, and the
compiler sha is unchanged at `495f325004e0`):

| | before | after |
| --- | --- | --- |
| `test_nilpy_min_max_key_in_a_variable` | FAIL (`expected a number, got object`) | **PASS** |
| `test_nilpy_min_max_key_none` | FAIL at row 2 | advances to row 4 (see below) |

Receiver x key matrix, all 8 rows green: {module, parameter} x {lambda, named
def, variable, None}. Nine neighbours re-run green (`max_min_iterables`,
`list_sort_key`, `list_sort_method`, `sort_lt_dunder`, `sorted_dict_key`,
`sorted_key_dispatch`, `sorted_key_none`, `sorted_pairs`, `sorted_sequences`),
plus the scalar surface the new overload could have shadowed — `min(1,2)`,
3- and 4-argument forms, `min("ab")`, dict receivers, `sorted` — no ambiguity
error and no changed answer.

`test_nilpy_min_max_key_none` is NOT closed by this and is filed blocked: its
row 4 is `min("cab", key=None)`, a **literal** str receiver, which is a separate
frontend defect — see
`regression-nilpy-a-literal-str-receiver-with-key-reaches-no-keyed-overload`.
- 2026-08-30 — resolved, commit PENDING-COMMIT.

- 2026-08-30 — resolved, commit PENDING-COMMIT.
