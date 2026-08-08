---
track: T
prio: 60
type: bug
summary: "twatch files a prio-70 stub on NEW-RED but never closes or annotates it when a later report moves the same job to FIXED, so a self-healing red outranks all real work indefinitely."
status: done
owner: claude-T@plexus
---

# A self-healed red leaves a permanent prio-70 stub at the head of the ranked queue

- **Track:** T (tools & testing). Files: `tools/twatch.py` (the stub-filing path).
- **Found:** 2026-08-06, working the N queue — the top TWO items by effective
  priority were both already-fixed reds.

## What happens

`twatch` auto-files a stub ticket into `devdocs/progress/backlog/` on NEW-RED,
with `prio: 70`. That is the right call: a fresh regression should outrank
feature work. But nothing ever takes it back. When a later report moves the same
job to **FIXED**, the stub is not closed, not annotated, not even re-prioritised.

Because 70 is above almost everything else in the backlog, and because
`tools/progress.sh next` ranks by effective priority, a red that healed on its
own **permanently occupies the head of the queue** and is handed to the next
agent that asks for work.

## Measured

Nine open auto-filed stubs on 2026-08-06. **All nine passed at HEAD** (`733be3321`,
compiler snapshot sha256 `cafd50517875`), each run with its own stub's repro line:

| stub's test | watcher trail |
| --- | --- |
| `test_cpyext_hello` | NEW-RED `34c41bd` → FIXED `aba953c` (~1h) |
| `test_cpyext_args_errors` | NEW-RED `34c41bd` → FIXED `aba953c` |
| `test_cpyext_containers` | NEW-RED `34c41bd` → FIXED `aba953c` |
| `test_cpyext_cython` | NEW-RED `34c41bd` → FIXED `aba953c` |
| `test_cpyext_markupsafe` | NEW-RED `34c41bd` → FIXED `aba953c` |
| `test_nilpy_dotted_package_import` | NEW-RED `34c41bd` → FIXED `aba953c` |
| `test_nilpy_qualifier_vs_cproc` | NEW-RED `34c41bd` → FIXED `8b9d08b` (~15min) |
| `test_nilpy_pyexpr_semantics` | NEW-RED `9294bce` → STILL-RED ×8 → FIXED `733be33` |
| `test_nilpy_augmented_assign_class_dunder` | NEW-RED `e8450c5` → STILL-RED ×18 → FIXED `733be33` |

The last two rows are the *healthy* case — a genuine regression, correctly
tracked STILL-RED across every report until a fix landed. Note the watcher
**does** know the answer: `FIXED` is a section it already emits. The gap is only
that the stub is not wired to it.

The six `34c41bd` rows are the pathology: they had been stale for a day, and
seven of the nine stubs were pure queue noise.

Second, smaller finding: `test_nilpy_augmented_assign_class_dunder` had **two**
stubs filed for it, one from the `test-core` job and one from `test-nilpy`, since
the same source is exercised by both. Whatever closes stubs should key on the
job, but dedupe by test source when filing.

## Suggested fix

In the same pass that emits the `## FIXED` section, for each job listed there:
resolve its stub if one is open — or, if closing from the watcher identity is
outside its write scope (face 1 writes ONLY `tstate/`, which is the rule and
should stay), then at minimum append a `FIXED at <sha>` line to the stub and drop
its `prio:` well below 70, and let face 2 do the actual close. Either way the
ranked queue stops advertising fixed work as the most urgent thing in the repo.

Worth considering: a `--tier` / `progress.sh check` assertion that no open
auto-filed stub's job is currently green, so this class of drift is caught by the
gate rather than by an agent noticing it manually.

## Gate
`tools/testmgr.py --tier full` green (T's own gate), plus a scratch bare repo
exercising the file→heal→close cycle end to end. Test the tooling with QUICK
tiers, never long runs.

## Log
- 2026-08-08 — resolved, commit PENDING-COMMIT.

---

## Resolution (Track T, 2026-08-08) — commit `16720bb5f`

**The main half was already done.** `close_stub_tickets()` landed 2026-08-02 in
`1dd53a8ec` and is wired to the FIXED pass, and the backlog held **zero**
stub-marked tickets when this was picked up — the nine-stale-stubs symptom is
gone. What remained was the ticket's "second, smaller finding".

### Dedupe by test source

One source can be reached by several jobs (`test/x.npy` runs under both
`test-core` and `test-nilpy`) while the slug is the JOB selector — so one
broken file filed two tickets. `stub_sources()` indexes
`{test source -> slug}` across every bucket, once per filing pass, skipping
zero-byte debris and anything without `STUB_MARKER` (an enriched body is
somebody's analysis, not a stub). Filing keys on the source and says so when it
declines; closing still keys on the job, exactly as specified.

### The consequence the ticket did not mention

With one stub covering N jobs, closing it because the job it was *named after*
went green strands a still-broken source with **no ticket and no way to get
one** — the sibling job is STILL-RED, not NEW-RED, and nothing files on
still-red. The dedupe alone would have traded two tickets for zero. So
`close_stub_tickets()` now keeps a stub open while its source is red in any job
of the report.

### Gate

As specified — the file→heal→close cycle end to end in a scratch dir, quick
tier, no repo needed: **`tools/devtest_stub_lifecycle.py`** (new). It covers
one-source-one-stub, a repeat pass adding nothing, the stub staying open while
a sibling job is red, and the close landing in `done/` with its sha and
attribution. All pass; `gate.sh quick` GREEN.

### Deliberately not done

The "worth considering" `progress.sh check` assertion that no open stub's job
is currently green. The auto-close plus the guard above handles this drift at
source; an assertion inside a tool every track runs is a wider blast radius
than the remaining gap justifies. Recorded rather than silently skipped — if
the drift reappears with `autoticket` off or the watcher down, that assertion
is the answer.

### Related

The empty-range half of this cluster is fixed in `315029d55`
([[bug-t-empty-range-regression-cannot-be-bisected]]). It mattered here:
`closed_regs` derives from `open_regressions`, so a red with an empty range
opened no entry and its stub was **structurally** unclosable. That precondition
is gone now.
