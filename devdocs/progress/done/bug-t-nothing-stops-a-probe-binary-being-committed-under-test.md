---
track: T
prio: 30
type: bug
status: done
owner: ""
created: 2026-09-06
blocked-by: []
summary: "Three unreferenced x86-64 ELF probe binaries reached origin under test/ from three different seats in ten days -- test/tgf (042bcbb32, 08-28), test/tfr_fpc (2dbea3b85, 09-02), test/trf (71b5bac58, 09-06) -- and nothing noticed. .gitignore covers test/test_* and test/tmp_*; an ad-hoc probe name matches neither and `git add -A` takes it. No pattern can fix this because the names are arbitrary by definition. check_test_wiring.py already enumerates files ADDED under test/ against origin/master, so it is one magic-number test away from catching it, and it already knows how to say why. Removed all three in the same commit that filed this."
---

# Nothing stops a probe binary being committed under `test/`

| file | landed | by |
| --- | --- | --- |
| `test/tgf` | `042bcbb32`, 2026-08-28 | a generics fix |
| `test/tfr_fpc` | `2dbea3b85`, 2026-09-02 | a test-wiring commit |
| `test/trf` | `71b5bac58`, 2026-09-06 | this ticket's author |

All three are `\177ELF` x86-64 executables. All three are referenced by nothing
— no Makefile rule, no script, no `.expected` — verified by grepping the whole
tree for each name. All three are the residue of the same act: building a probe
with an ad-hoc output name inside the repo and then running `git add -A`.

## Why `.gitignore` cannot be the fix

`test/test_*` and `test/tmp_*` are there and are correct. A probe called `trf`
matches neither, and **the names are arbitrary by definition** — that is what
makes them ad-hoc. Adding `test/trf` to the ignore list fixes exactly one
future instance of an unbounded set.

## Why `check_test_wiring.py` is the right home

It already does the hard half. It enumerates every file **added under `test/`
since `origin/master`** (committed, staged or untracked), it already runs in
`gate.sh quick`, and it already knows how to print a refusal that says what to
do. A file whose first four bytes are `\177ELF` is not a test source and is
never a fixture, so the check is a magic-number read on a list it has already
built — with `test/UNWIRED.txt` as the escape hatch if anyone ever needs one.

It also has the property that matters: **it fires before the push**, which is
the only moment the fix is free.

## Why this is not filed as "add it to gate.sh"

`gate.sh` is run by every seat on this box and `/bin/sh` reads a script
INCREMENTALLY — editing one that is currently running corrupts that run and
returns an rc no test can produce (CLAUDE.md, "DO NOT TOUCH THE INSTRUMENT
WHILE IT IS MEASURING"). A peer said they were starting a gate as this was
found. The check belongs in the Python tool, which is loaded whole.

## Note for whoever takes it

The positive control is easy and must be drawn from the right population:
assert that a **committed** ELF under `test/` is rejected, not merely an
untracked one — two of the three above were committed and pushed, and a check
that only looks at untracked files would have passed on all three.

## 2026-09-06 (frankA) — done, and the filing's own mitigation does not hold

`check_test_wiring.py` now reads the first four bytes of every path
`added_since()` returns and refuses `\177ELF`, before the `SUBJECT_EXT` filter
narrows that list to test sources — which mattered, because a probe called
`trf` has no extension and was being dropped one line earlier. `gate.sh quick`
already invokes the tool with `--since origin/$GATE_BRANCH`, so it fires at
every seat with no gate.sh edit, which is what the filing asked for and why.

Five devtest cases in `check_test_wiring_devtest.py`, and the controls are on
the axis the filing named: a COMMITTED ELF (two of the three real ones were
committed, so an untracked-only guard would have passed on them), an UNTRACKED
one, one named `qq7` so no pattern could have anticipated it, a text `.pas`
asserting the *wiring* message and not the binary one — it fails either way, so
`rc == 1` alone proves nothing there — and an `UNWIRED.txt` entry still opening
the gate. Verified by DISABLING the guard: the three positive cases fail, the
two negative ones stay green.

**THE FILING'S MITIGATION IS FALSE, AND I PRODUCED A FOURTH INSTANCE PROVING
IT.** `.gitignore` says *"Build probes OUTSIDE the repo (the session
scratchpad) and this cannot happen."* It can. `fpc -o<name> <path>/x.pas`
writes `<name>` **next to the SOURCE**, not into the current directory —
measured directly: source in one directory, cwd in another, the binary landed
beside the source and the cwd stayed empty. So a session that does the
prescribed thing, sits in its scratchpad, and diffs a repo fixture against fpc
still drops an executable into `test/`. That is the commonest reason anyone
runs fpc in this tree, and it is how `test/copyfpc` appeared here hours after
the first three were removed — caught by `git status` before the commit, by
luck rather than by an instrument.

Being outside the repo is not the property that matters; **spelling the output
path is**. The refusal message says so, because the advice a guard prints is
the only advice its reader gets.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 8b4310597.
