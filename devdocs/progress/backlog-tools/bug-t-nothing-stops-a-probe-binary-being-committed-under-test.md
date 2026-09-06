---
track: T
prio: 30
type: bug
status: backlog
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
