---
prio: 70
track: N
status: done
owner: frankA
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

---

## Resolved 2026-08-29 — frankA

### The triage above named the wrong suspect, and the ticket's own title is a red herring

`19dc5586e` is not the cause. Neither is instantiation order, inheritance, or
the `a`/`A` name collision the test file's header is about. The minimal repro
has none of them:

```python
class C:
    def hello(self):
        return "C"

def make():
    c = C()
    return c.hello()

print(make())      # segfault
```

Renaming the local to `q` still crashes, so it is not the class-name collision.
An `int`-returning method crashes too, so it is not string ownership. Moving the
call one statement earlier — `t = c.hello(); return t` — is **correct**, which
places the defect in the def's RETURN-TYPE SCAN rather than in the call.

`PXXDBG=n.ret` says it outright: `def@18 make tk=6 rec=16` — tk 6 is `tyClass`,
rec 16 is `REC_UCLASS_BASE + C`. The def is typed as **the receiver's class**,
with `.hello()` ignored, and the caller then reads a returned string handle as
an object pointer.

### It is a sibling that was never grepped for

`pyparser.inc`'s own comment, written when the FIELD form was fixed:

> `return q.n` — the whole return is a FIELD READ off a local. The scans above
> answer the RECEIVER's class (tyClass Item) while the value is the field's own
> type
> — bug-nilpy-a-def-returning-a-field-is-typed-as-the-receivers-class

Same sentence describes this bug with one word changed. `PyRetFieldType` was
added for `e = j + 4` (`recv . member`); the `recv . member ( args )` shape was
left to fall through to the expression chase, which chases the receiver name to
its `c = C()` binding and answers the class. CLAUDE.md's rule is literal here —
*if you fix a bug on one arm of a double case, grep for the sibling before
closing the ticket* — and the call arm is the **worse** half: a field read
printed the right value (an int renders through the int path), while a method
call segfaults with no wrong value to notice first.

### The fix

Normalised rather than duplicated, per `normalise-dont-special-case.md`. The two
arms are the same question about the same receiver and differ only in which
member table they then ask, so the receiver chase is now written once:

- `PyRetRecvClass` — the local's class from its last `recv = ClassName(`
  binding. Extracted from `PyRetFieldType`, which now calls it.
- `PyRetMethodType` — the method sibling: same chase, then `FindUMeth` →
  `Procs[].RetType` / `ProcRetRecId`.
- The caller arm sits directly beside the field arm so the pair is visible.

Two decisions worth recording:

1. **Receiver known but method unresolvable ⇒ `tyVariant`, not fallthrough.**
   Falling through is exactly what lets the chase claim the receiver's class.
   Claiming the class is the bug; the fallback is not. This is the same call the
   ctor-selector arm already made.
2. **Receiver not a local of this body ⇒ untouched.** `math.sqrt(2.0)` is a
   module-qualified call and keeps its route — the control that the
   intrinsic-collision family (`PyIsClassTypeExact`, `PyIsExactCtorName`,
   `PyDottedRootIsLocal`) exists to protect.

`PyRetRecvClass` also resolves a receiver bound from a **def** returning an
instance (`c = get()`), which was the one probe still segfaulting after the
constructor form worked. Guarded against the `FindProc` case-folding hazard by
demanding a class return with a real rec id — no intrinsic has one.

### Measured

Twenty probes mapping the boundary; all green, and the ten that crashed before
are the ten this changes. Controls verified against **CPython**, not against
expectation: `math.sqrt`, a builtin conversion, and a str method on a local all
match.

`test/test_nilpy_def_returning_a_field` extended with the method sibling of
every row it already had — int/str/class/args returns, an inherited override, a
receiver bound from a def, the two-statement control, and the three
module/builtin controls. Ten new rows, expectations generated by running the
file under CPython.

**Baseline run, as required:** on `pinned` the extended test SEGFAULTS after row
13 and prints none of the ten new rows; on the fix it matches CPython on all 23.
The regression's own test now matches its `.expected` exactly.

Canaries chosen by MECHANISM (def return-type inference), not by topic — the
correction I owed after choosing ten canaries by string *topic* earlier today
and writing a regression none of them could see: 28 NilPy tests across return
inference, method dispatch, selector chains, variant receivers, intrinsic
shadowing and lambda returns. All green.

Self-host fixedpoint `321f9f53086f`, converged in 1 round.
- 2026-08-29 — resolved, commit f245e918e.
