---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 47 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_min_max_key_none.npy red at 0200df7eabcd (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T02:33:24Z
- **Test source:** test/test_nilpy_min_max_key_none.npy test/test_nilpy_min_max_key_none.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_min_max_key_none.npy'` at 0200df7eabcd33796c0f7ac151b80aafbf75b5fb

## Range
> **The named sha `0200df7eabcd` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0200df7eabcd`, last good `3f854c927aac`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3750893/test_nilpy_mmkeynone26  [code=1265231B  data=55455B  bss=52028B  procs=1862]
Unhandled exception: TypeError: expected a number, got object
--- test/test_nilpy_min_max_key_none.expected	2026-08-29 16:03:42.852941360 +0000
+++ -	2026-08-30 02:07:44.379079193 +0000
@@ -1,9 +1,2 @@
 1 3
 1 3
-(2, 9)
-a c
-0 2
-3 1
-1 2 1 2
-1.5 b
-(1, 9) [2]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-08-30 — triaged (frankB). Same cause as the key-in-a-variable regression.

**Track N is correct** — `compiler/builtin/pylib.pas` + `compiler/pyparser.inc`,
not `lib/**`. Reproduces at the current pin v394 `53800fbeb0b66e11`, so it is not
one of the "already fixed" cases.

**This is one defect with the sibling ticket
[[regression-test-nilpy-test-nilpy-min-max-key-in-a-variable]], not two.** The
full analysis, the matrix, the minimal repro and the candidate commit are there;
this note records only what is specific to this test.

The trigger is a **variant receiver** (a sequence arriving as a function
parameter) plus a key that is not an inline-lambda node. `key=None` is one column
of that table and `key=<variable>` is another — which is why the two tests fail
with a byte-identical exception string.

Visible directly in this test's own output: **lines 1 and 2 pass.**

```python
print(min([3, 1], key=None), max([3, 1], key=None))   # 1 3   — passes
k = None
print(min([3, 1], key=k), max([3, 1], key=k))         # 1 3   — passes
```

Both are module-level with a literal list, so both take the static-list arm that
the earlier fix repaired. The first failure is the very next statement — the
`show()` helper, where `xs` is a parameter and the receiver becomes a variant:

```python
def show(xs, key=None):
    return (min(xs, key=key), max(xs, key=key))
```

So `key=None` is not itself broken. It is broken **only through a variant
receiver**, and this test happens to be the one that reaches that arm through a
helper — which is also the most common way real code writes it, since an optional
`key=None` threaded through a helper's own default is the idiom the test's header
comment names.

One fix closes both. Gate them together.

### Carried here so this ticket stands alone

The two tickets are ranked separately at p70, so this one can be dispatched on
its own. The pointer above is not enough if you never follow it — these three
items are the ones that change what you do, repeated rather than referenced:

**The receiver table** (`min(xs, key=K)`; CPython gives 9 for the callable keys,
2 for `None`):

| receiver | `key=lambda x: -x` | `key=pk` (def name) | `key=f` (variable) | `key=None` |
| --- | --- | --- | --- | --- |
| module-level `xs = [5,2,9]` | 9 | 9 | 9 | 2 |
| **function parameter `xs`** | 9 | **TypeError** | **TypeError** | **TypeError** |

**Prior art:** [[bug-nilpy-min-max-with-a-key-held-in-a-variable-picks-the-numeric-overload]]
(done, `256b21957`) fixed this family for the **static-list** receiver; every row
of its own table still passes. The **variant-container** arm is the half that is
red, and that ticket's fix note names both shapes as the two `PyMinMaxByKey` was
made the single meeting point for — so one arm breaking is the expected shape of
a break here, not a new mystery.

**Candidate cause — do not record it as the cause without building it.**
`7b73a385d feat(N): list.sort(key=)` is the only commit in the watcher's
6-commit range touching `compiler/builtin/pylib.pas` or `compiler/pyparser.inc`,
and it refactors the callable→Pointer coercion the earlier fix rests on, adding
`pyvar_callable_ptr_opt` for the `key=None` spelling. **That is circumstantial.**
Build `7b73a385d~1` and `7b73a385d` and run the table above on both before
writing a cause into either ticket. The named sha `0200df7eabcd` remains
impossible (it touches no buildable file). A plausible attribution nobody diffed
is the failure this repo has recorded most often, and this ticket is reachable
without ever reading the sibling that says so.
