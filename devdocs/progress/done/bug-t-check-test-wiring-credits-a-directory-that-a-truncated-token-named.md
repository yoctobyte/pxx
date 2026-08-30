---
slug: bug-t-check-test-wiring-credits-a-directory-that-a-truncated-token-named
title: "check_test_wiring credits a whole directory to a token that ran nothing — five orphans hide in test/gui"
track: T
type: bug
prio: 45
status: done
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

## CORRECTION — one source, not three, and the census was wrong the same way twice

The section that stood here listed **three** sources of a false directory token
and gave "prose in a comment" as one of them, citing
`tools/install_lib_candidates.sh:350`. **That is wrong.** `wired_paths()` has
stripped full-line comments since the csqlite_file_probe fix, so a `#`-led line
is not collected at all and never was a source. The census that produced the
table did not apply the tool's own filter — it reproduced a defect the tool had
already fixed, and then reported it as live.

That is the third time in this session a census has agreed with itself instead
of with the thing it measures, and it is the same mechanism each time: the
instrument was pointed at the source text without the filter the real code
applies. It was caught here only because reading `wired_paths()` to write the
fix showed the comment-stripping loop sitting in it. Recorded rather than
quietly deleted, because the correction is the finding.

**Re-censused with the tool's own full-line-comment filter applied**, 42 tokens
read as directory references. All but a handful are legitimate `-Fu`/`-I` search
paths or globs. What is actually wrong:

| source | example | blanketed | consequence |
| --- | --- | --- | --- |
| **a shell variable truncating a path** | `tools/gui_suite.sh:28` `$ROOT/test/gui/$name.pas` | 26 | **five files run by nothing, reported as zero** |
| **the checker's own source** | `tools/check_test_wiring.py:43` `SKIP_DIRS = (…)` | 11 | none today — those dirs are skipped anyway |

Two sources, and only the first has a victim. The second still gets fixed: the
tool is reading its own documentation as evidence, and the next path written
into that literal would silently exempt whatever it names with no rule behind
it. Same family as a census matching the comment that explains it.

Two more directory blankets were checked and are **correct**, which matters
because a stricter rule must not break them: `test/fgl` (`DRIVERS="$ROOT/test/fgl"`,
and the script does run every driver in it) and `test/nilpy_units/pkgcorpus`
(`cd test/nilpy_units/pkgcorpus && …`, a package corpus imported wholesale).
Both name the directory *completely* — no trailing slash — which is what the fix
keys on.

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

---

## Fixed — 2026-08-29

`tools/check_test_wiring.py` + six new guards in
`tools/check_test_wiring_devtest.py`. The report goes **0 → 6** under
`test/gui/`, and every one of the six is real.

### The rule that replaced "a slash and no extension"

A new `classify_dir_ref(tok, line, end)` decides whether a token reaches a whole
directory, and **the trailing slash is the tell**:

- `test/fgl`, `test/case_units`, `test/nilpy_units/pkgcorpus` — the token *ends
  at the directory name because the text did*. A real reference; credited.
- `test/gui/` — the token ends at a `/` because the pattern hit something it
  cannot match, i.e. a variable. Truncated: it names a file we cannot see, not
  the directory. Not credited.
- the one truncation that IS a directory reference is a **glob** over its
  contents (`for p in test/lua/*.lua`), so a `*` immediately after the token
  keeps the credit.
- and the token must actually **be** a directory — `test/test_asm_emit_$$t.pas`
  truncates to `test/test_asm_emit_`, which has a slash, has no extension, and
  is not a directory at all.

Plus: the checker no longer scans its own source.

### The half that isn't in the ticket's original diagnosis

Killing the blanket outright turned **ten** files red that `gui_suite.sh` really
does run — it supplies `$name` as a bare word (`run_gui_test test_pcl_click`),
which the path-token pattern cannot see. Ten false reds is the noisy failure
direction rather than the silent one, but it is still wrong, and the checker's
own docstring names it: *"Reporting them would train people to ignore the check,
which costs more than the gaps it finds."*

So a truncated directory token now credits exactly the files in that directory
whose **stem the same file names as a bare word**, and nothing else. That is
what separates the ten `test_pcl_*` cases gui_suite runs from the five beside
them that it does not — a distinction the blanket erased in the direction that
hides work.

One tightening, measured rather than anticipated: the first stem match also
credited `test/gui/helloworld/main.pas`, because gui_suite names
`$ROOT/apps/ide/eliah/main.pas` — a **different file that merely shares a
stem**, reached through a path component. The lookbehind now excludes `/`, and
`main.pas` is correctly reported. It is the sixth orphan.

### Guards

Six added, and the four that could discriminate were **run against the old
checker and confirmed to fail there**:

| guard | on the old code |
| --- | --- |
| a variable-truncated path does not blanket its directory | **FAIL** |
| a bare stem in the same script credits that file, and only it | **FAIL** |
| a same-stem path component elsewhere is not evidence | **FAIL** |
| the checker does not read its own source as evidence | **FAIL** |
| a glob over a directory still blankets it | passes both — regression pin |
| a -Fu<dir> search path still blankets its directory | passes both — regression pin |

A guard that has never failed is a guard that has never been tested. The two
regression pins are labelled as such rather than counted as coverage.

`tools/check_test_wiring_devtest.py`: 17 guards, all green.

### What the fix does NOT do

It does not wire the six files it reveals, and they do not block anything. That
is [[chore-t-six-orphan-gui-tests-the-blanket-was-hiding]]. Making the
instrument stop lying is bounded and pays immediately; wiring an unknown tail is
open-ended work of unknown value.

## Log
- 2026-08-29 — resolved, commit b76d7461e.

---

## Follow-up, same day: the write-up cleared one of its own findings

The fix landed, the report read **6**, and then it read **5** — because of the
commit that fixed it.

Two mentions of `test/gui/helloworld/main.pas` in prose credited the file:

1. **The devtest's docstring.** `wired_paths()` strips *full-line* comments
   only, and says so — *"Prose inside a Python docstring is likewise still
   counted as a reference."* So the sentence explaining why that file is an
   orphan became the evidence that something runs it. Reworded to name the file
   without a live `test/` token, with a note in place saying why the spelling
   matters.

2. **The stem rule, descending into a subdirectory.** The devtest carries the
   token `test/gui/` inside a *fixture string* and defines its own `def main()`
   at the bottom, and the new stem rule matched that bare `main` against
   `test/gui/helloworld/main.pas`. Fixed properly rather than by rewording: a
   truncated token `test/gui/$name.pas` ends at the variable with `.pas` after
   it, so it can only name a file **directly** in that directory, never one two
   levels down. Stem evidence is now restricted to direct children, and a
   seventh guard pins it.

Worth recording rather than quietly squashing, because it is the third distinct
instance of one shape in a single ticket:

| the witness | what it cleared |
| --- | --- |
| the checker's own `SKIP_DIRS` literal | the directories that literal lists |
| the devtest's docstring describing the orphan | that orphan |
| the devtest's own `def main()` | a file two directories away |

**A tool that scans prose in its own directory will eventually read its own
documentation as data.** The first was harmless, the second and third were not,
and none of them was visible in the tool's output — the report simply got
shorter. The general hazard is untouched and deliberately so: whether a `tools/`
script *mentions* or *runs* a path is the judgement the checker refuses to guess
at (that is why the STALE verdict was downgraded to an advisory). What changed
here is only that the checker no longer reads itself, and that stem evidence
cannot reach past a directory the token could not have named.

Devtest: **18 guards**, all green.
