---
track: N
prio: 40
type: bug
blocked-by: []
summary: "The tk loop in `test-nilpy` spells its BINARIES by full path — that was the callbacks fix — but still captures output to `$(TESTTMP)/$$src.got`. `make -n` yields `/tmp/$src.got`, which testmgr's filename scan cannot match, so those three files are never privatized and two concurrent runs share them. Found by T's new lint, in the recipe whose earlier fix was believed complete."
---

# The tk `.got` capture files are invisible to testmgr's privatization

Found 2026-08-19 by Track T (plexus-T), on the first run of the lint added for
[[bug-t-split-jobs-misses-a-tmp-path-reached-through-a-shell-variable]].
**Filed for routing — T owns the tool, the owning lane owns the recipe.**

## What is still there

`Makefile:376-381`, inside `test-nilpy`:

```make
for t in tkinter_facade:$(TESTTMP)/test_nilpy_tkinter26 \
         field_class_identity:$(TESTTMP)/test_nilpy_fldcls26 \
         callbacks:$(TESTTMP)/test_nilpy_tkcb26; do \
  src=$${t%%:*}; bin=$${t##*:}; \
  timeout 120 xvfb-run -a $$bin > $(TESTTMP)/$$src.got 2>&1 \
    || { echo "  tk: $$src EXITED NONZERO under Xvfb"; cat $(TESTTMP)/$$src.got; exit 1; }; \
  diff -u examples/tk/$$src.expected $(TESTTMP)/$$src.got \
    || { echo "  tk: $$src OUTPUT CHANGED"; exit 1; }; \
done; \
```

`9f11b405d` fixed the **binaries**: the item list now spells each one by full
path, so union-find sees the literals and the three jobs merged into one ordered
job. That was the right fix and it closed the callbacks red.

**The `.got` capture files were not part of it.** `$(TESTTMP)/$$src.got` becomes
`/tmp/$src.got` in `make -n`, and testmgr's `tmp_re` (`/tmp/[A-Za-z0-9_./+-]+`)
does not match it — `$` is not in the class, so the token is not merely wrong,
it is **absent**.

## Why it still matters with the merge already fixed

The merge half is genuinely fixed; this is the **privatization** half, which is a
different mechanism with a different consequence:

- testmgr rewrites literal `/tmp` paths in the recipe text it executes, so two
  concurrent runs get their own scratch. It cannot rewrite what it cannot see.
- So `/tmp/tkinter_facade.got`, `/tmp/field_class_identity.got` and
  `/tmp/callbacks.got` are **shared across every concurrent run on the box** —
  and this box runs two clones' testmgrs by design (the watcher's plus a dev
  checkout), which is the documented co-tenancy in `devdocs/dev/track-t.md`.
- The failure it produces is **`tk: <src> OUTPUT CHANGED`** — a diff against the
  expected file, i.e. it presents as a NilPy tk regression rather than as a
  collision. Same shape as the UDP port collision recorded in `track-t.md`: the
  loser of a race on a shared global does not fail as a hang, it answers with
  someone else's data and the red arrives with a plausible wrong diagnosis
  attached.

Not yet observed in the wild. Filed because it is cheap to close and expensive to
triage, and because the class has now bitten this exact recipe once already.

## The fix

Same shape as the one that landed: state the path in the recipe rather than
building it from a variable. The item list already carries `src:bin`; a third
field, or a second full-path spelling, makes the `.got` visible to the scan:

```make
for t in tkinter_facade:$(TESTTMP)/test_nilpy_tkinter26:$(TESTTMP)/tkinter_facade.got \
```

Then `got=$${t##*:}` and use `$$got`. Any spelling works as long as every
`/tmp` path the recipe touches appears **literally** in `make -n` output.

## Guard

`tools/testmgr_tmp_var_devtest.py` carries this as its one `KNOWN` entry, so it
prints on every run rather than being silently tolerated. **When this is fixed,
delete that entry** — the devtest already prints an explicit "no longer reaches
/tmp through a variable — remove it from KNOWN and close its ticket" when a
known-open instance clears.
