---
slug: bug-t-check-test-wiring-credits-a-directory-that-a-truncated-token-named
title: "check_test_wiring credits a whole directory to a token that ran nothing — five orphans hide in test/gui"
track: T
type: bug
prio: 45
status: backlog
found: 2026-08-29
found-by: pxx-a5 (Track T)
blocks: [chore-a-wire-the-nine-passing-orphan-tests-and-gate-check-test-wiring]
---

# A directory reference is credited from any token that looks like one

`tools/check_test_wiring.py` reports **0 unwired files under `test/gui/`**.
Five of the seventeen `.pas` subjects there are run by nothing:

```
test/gui/test_gtk_signals.pas       test/gui/test_pcl_showmessage.pas
test/gui/test_gtk_window.pas        test/gui/test_pcl_window.pas
test/gui/test_pcl_helloworld.pas
```

`grep -rl <stem> Makefile tools/` returns nothing for any of them. frank-b
found two of the five by hand during the PCL header migration
([[chore-a-wire-the-nine-passing-orphan-tests-and-gate-check-test-wiring]]);
the checker had already certified all five.

## The mechanism, and it is one line

`consumed_by()` credits every file under a directory that anything names —
correctly, because `-Futest/case_units` names a directory and never the unit
inside it. A token counts as a directory when it has a `/` and **no extension**:

```python
dirs = {w.rstrip("/") for w in wired
        if w.count("/") >= 1 and not os.path.splitext(w)[1]}
```

The collector's pattern is `test/[A-Za-z0-9_./+-]+`, and `$` is not in that
class. So `tools/gui_suite.sh:28`

```sh
local src="$ROOT/test/gui/$name.pas"
```

yields the token `test/gui/` — the variable truncates it — which rstrips to
`test/gui`, has no extension, and **blankets all 26 tracked files in the
directory**. The line that causes it is the very line that proves only *some*
of them run.

The failure is silent and one-directional: it can only ever *remove* files from
the report, never add one. That is the worst direction for a check whose entire
output is a list of what nobody is running.

## Three sources of a false directory token, all present today

Censused across `Makefile` and `tools/**` (script in the ticket's commit
message; 33 tokens read as directory references, most of them legitimate
`-Fu`/`-I`/glob references):

| source | example | blanketed |
| --- | --- | --- |
| **a shell variable truncating a path** | `tools/gui_suite.sh:28` `$ROOT/test/gui/$name.pas` | 26 |
| **prose in a comment** | `tools/install_lib_candidates.sh:350` "…live in the repo under `test/fpjson/.`" | 2 |
| **the checker's own source** | `tools/check_test_wiring.py:43` `SKIP_DIRS = ("test/pascal-conformance/", …)` | 6 |

The third is the one worth naming out loud, because it is this session's
recurring shape in a new place: **the checker scans `tools/**` for references,
and it is itself in `tools/`, so its own `SKIP_DIRS` literal credits the
directories it lists.** Those particular six are skipped anyway so nothing is
lost today — but the tool is reading its own documentation as evidence, and the
next literal path someone writes into it will silently exempt whatever it names.
Same defect as a census that matched the comment explaining the census.

## Fix

Narrow the directory rule to references that actually *mean* a directory:

- a token immediately preceded by `-Fu` / `-Fi` / `-I` (the search-path flags
  the rule was written for);
- a glob over the directory (`for p in test/lua/*.lua`), which does run them all;

and stop crediting a bare truncated path. Then **exclude
`tools/check_test_wiring.py` itself from the scanned set** — a tool must not be
its own witness.

Expect the report to grow by roughly the 26 `test/gui` entries less the eleven
that `gui_suite.sh` genuinely runs, plus a handful from the prose tokens. That
growth is the point; it is what the check was supposed to have been saying.

## Why this blocks the gate

[[chore-a-wire-the-nine-passing-orphan-tests-and-gate-check-test-wiring]] ends
in wiring this checker into `make test`. Gating it in its current state would
promote a **false all-clear** to a build-breaking authority: the twelve
`test_pyeval_*` files are visible and will be wired, the report will read zero,
and five confirmed orphans will still be running nowhere with a green check
standing over them. A check that is wrong in the reassuring direction is worse
than no check, which is the same reasoning the parent used to refuse gating
something red on arrival — the other half of it.
