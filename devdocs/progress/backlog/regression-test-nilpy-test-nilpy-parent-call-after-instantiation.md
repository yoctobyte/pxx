---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 11 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_parent_call_after_instantiation.npy red at b898d0543fc8 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-27T20:46:31Z
- **Test source:** test/test_nilpy_parent_call_after_instantiation.npy test/test_nilpy_parent_call_after_instantiation.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_parent_call_after_instantiation.npy'` at b898d0543fc8499facc66706257ff08d39195520

## Range
> **The named sha `b898d0543fc8` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b898d0543fc8`, last good `8b2cc332791e`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-25046/test_nilpy_parentcall26  [code=1271989B  data=57044B  bss=42108B  procs=1810]
--- test/test_nilpy_parent_call_after_instantiation.expected	2026-08-02 15:18:13.701581110 +0200
+++ -	2026-08-27 22:40:16.217688721 +0200
@@ -1,4 +1,2 @@
 E:A A
 F:B B
-C G:C
-H:G:C
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## Track T triage, 2026-08-27 — this IS a real NEW-RED, and here is a usable range

**It is not a first-report.** The concern is legitimate in general —
`diff_jobs()` asks the was-it-passing question with
`prev_jobs.get(name, "pass")`, so a job never seen before arrives as a NEW-RED
against a green history it never had. That is **not** what happened here.
Walking the committed history of `tstate/plexus.json`, this job's recorded
status was:

| tstate commit | run date | status |
|---|---|---|
| `854c315fe` | 2026-08-27T20:26:39Z | **pass** |
| `c0840ac21` | 2026-08-27T20:53:44Z | **fail** |

A real recorded green immediately prior. The regression is genuine.

**Ignore the `bad=` in the stub.** `b898d0543fc8` is docs-only
(`devdocs/dev/session-roster.md`); nothing in it can break a NilPy test. It is
the sha that was TESTED, not a cause — with buildable commits swept only
incidentally, a bisect has no fine-grained ladder to land on.

**The honest range, and it is short.** `test-nilpy` runs in the
**limited/full** tiers only, so a `native` run does not refresh these job
entries — the map carries them forward. The last-good is therefore the last
*deep* run, not the last run of any tier:

- last full run with **0** nilpy new-reds: `8b2cc332791e` @ 20:09:39Z
- first full run reporting this red: `b898d0543fc8` @ 20:46:26Z

Seventeen commits sit between them and **only two touch a buildable file**:

| sha | commit | lane |
|---|---|---|
| `218ce1eaf` | fix(rtl): AnsiQuotedStr, and TryStr* zeroes its value on failure | B |
| `19dc5586e` | fix(nilpy): type a method call by the METHOD, not a same-named intrinsic | N |

**`19dc5586e` is the prime suspect** — it changes how a method call is typed
when an intrinsic shares the name, which is the exact shape of both failing
tests (a parent method call; `startswith`, which is both a string method and an
intrinsic). Start there, and confirm by building at `8b2cc332791e` vs
`19dc5586e` rather than by reading the diff.

*Triaged by Track T (face 2) from tstate; the fix belongs to the owning lane.*
