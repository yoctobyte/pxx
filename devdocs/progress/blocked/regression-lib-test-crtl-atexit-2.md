---
summary: "NOT ACTIONABLE AND NOT THE SLUG'S SUBJECT: crtl_atexit passes. The census step fails because it runs under $(PXX_STABLE) and the pinned compiler warns on a WEAK external. The fix (e4c72bd15) landed 18 minutes AFTER pin v410. Live compiler: 600 declared, all defined, rc=0. Clears itself at the next pin; there is nothing to fix."
type: regression
track: C
prio: 70
status: blocked
---

> **Track guessed as C from the FAILING STEP** — line 15 of 17, `sh test/crtl_declaration_census.sh stable_linux_amd64/default/pinned /tmp`, which names `test/crtl_declaration_census.sh`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **The SLUG names `crtl_atexit`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `crtl_declaration_census`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/crtl_atexit.c at 934ba04180e9 in step 15/17, `sh test/crtl_declaration_census.sh stable_linux_amd64/default/pinned /tmp` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-14T17:57:27Z
- **Test source:** test/crtl_atexit.c tools/expect_same.sh +1
- **Failing step:** line 15 of 17 of the job's recipe; it names `test/crtl_declaration_census.sh`.
  ```
  sh test/crtl_declaration_census.sh stable_linux_amd64/default/pinned /tmp
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/crtl_atexit.c'` at 934ba04180e95d273bc57583fc2d8311cd0a96e8

## Range
bad `934ba04180e9`, last good `b984ad07e38f`, **1 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
pascal26:218: error: expected 'begin' before 'weakexternal'
(tail)
ok: /tmp/testmgr-scratch-3543567/crtl_atexit  [code=327448B  data=13304B  bss=76520B  procs=873]
main-returns
h3
h2
h1
via-exit
child-exit
via-_Exit
  lib-test: crtl_atexit is self-contained (no DT_NEEDED)
FAIL: census TU did not compile
pascal26:218: error: expected 'begin' before 'weakexternal'
  in: stable_linux_amd64/default/../../lib/rtl/palthread.pas
  near: ) : Integer ; cdecl ; >>> weakexternal 'libc.so.6' name 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## STATUS 2026-09-16 (frankb-56) — INERT UNTIL PINNED. Do not claim this; there is nothing to fix.

**Three things in the header above are stale. Read this block instead.**

1. **`crtl_atexit` is not the subject and it PASSES** — the header's own warning
   said so and it is worth repeating, because the slug is what `next` shows you.
2. **`weakexternal` no longer fails to parse.** That was the 2026-09-14 symptom
   in the log tail. Pin v410 carries `934ba0418`, so the keyword parses now.
3. **The cause underneath changed.** The census now fails on
   `crtl declares functions it does not define: c_pthread_create` — a name that
   **appears nowhere in `lib/crtl`**. It is not a missing definition. It is
   `CWarnImplicitSystemImports` warning about a WEAK external, which is not an
   implicit import at all: unresolved, its GOT slot is zero, the call site takes
   its guarded branch, and `DropWeakOnlyImports` can remove it entirely.

**THE FIX IS ALREADY LANDED. IT IS NOT IN THE PIN.**

| | |
| --- | --- |
| guard `if ProcWeakExternal[procIdx] then continue` | `e4c72bd15`, 2026-09-14 **21:03:57** |
| pin v410 (`$(PXX_STABLE)`) | `764ee2ed2`, 2026-09-14 **20:45:16** |
| `git merge-base --is-ancestor e4c72bd15 764ee2ed2` | **false** |

**Eighteen minutes.** The fix missed the pin by eighteen minutes, and a compiler
fix is inert until pinned.

**The differential — same script, same tree, only the compiler differs:**

```
PINNED  sh test/crtl_declaration_census.sh stable_linux_amd64/default/pinned
        FAIL: crtl declares functions it does not define: c_pthread_create   rc=1
LIVE    sh test/crtl_declaration_census.sh ./compiler/pascal26
        crtl declaration census — 600 declared, all defined, no libc imports  rc=0
```

**The census is not wrong and must not be loosened.** Its header records four
real defects it caught, and its name list is generated per run precisely so it
cannot go stale. The warning was answering about the wrong population; the
census faithfully reported what the warning said. Both instruments behaved
correctly and the red is real about the PIN.

**What clears it:** the next `make pin`. No code change, no action available to
a dev seat. Moved out of `backlog/` so the ranker stops handing a p70 with no
work in it to successive seats — this is the second seat to re-derive it.

**Re-laning note:** the auto-filer guessed track C from the failing step's path.
That guess is not wrong (the guard lives in `compiler/cparser.inc`, C frontend)
but it is also not useful, because no lane can act on this.

## RE-VERIFIED 2026-09-16, both instruments — still inert-until-pinned, still nothing to fix

Raised again as one of the rows standing between the tree and goal 1, quoting
`crtl declares functions it does not define: c_pthread_create`. That reason is
**true of the pinned compiler and false of the tree**, which is the whole
content of this ticket and is worth re-measuring rather than re-reading.

| | |
| --- | --- |
| census under `compiler/pascal26` | `601 declared, all defined, no libc imports`, rc=0 |
| census under `$(PXX_STABLE)` | `FAIL: crtl declares functions it does not define: c_pthread_create` |
| pin v410 (`764ee2ed2`) committed | 2026-09-14 **20:45:16** |
| fix `e4c72bd15` committed | 2026-09-14 **21:03:57** — 18 minutes later |
| `merge-base --is-ancestor e4c72bd15 764ee2ed2` | **no** |
| pinned binary on disk | `c599e8546121`, which is the sha the pin commit records |

So the row is **not work**: it is a fix that exists and is not yet carried by a
pin. It clears itself at the next one. Counting it among the things that need
FIXING overstates the distance to goal 1 by one.

### A grep trap on the way, recorded because it nearly reversed the verdict

`git log --grep='pin v410'` returned `c9af737b5` — a `docs(watch)` commit that
merely **mentions** pin v410 in its prose. Tested against that, the fix came
back as an ancestor, i.e. *"the pin contains the fix"*, which is the opposite of
the truth and would have made this look like a live defect. The pin commit is
`^chore(stable): pin v410`, anchored, and against the real one the fix is
correctly NOT an ancestor.

Same shape as the `grep -o "663"` that matched `code=417346B` an hour earlier in
another seat's hands: **a grep for a name matches prose about the thing as
readily as the thing.** Anchor the pattern to the commit-subject form, and
prefer the recorded binary sha — `c599e8546121` appears in the pin's own subject
line and on disk, and that pair is an identity no prose can imitate.
