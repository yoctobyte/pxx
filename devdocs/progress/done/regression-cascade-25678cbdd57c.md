---
prio: 90
---

# regression CASCADE: 60 jobs newly red at 25678cbdd57c (auto-filed by twatch)

- **Type:** regression cascade (auto-filed by Track T watcher, host xeon).
  Untriaged. 60 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-08-01T02:56:33Z
- **Root-cause suspects in the red set:** none of the known root jobs — likely a broken build or harness event

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier native --job '<job>'` at 25678cbdd57c6ec9ce3d529e995fe0cc57c3ab84

## Newly red jobs
- `test-asm#src:compiler/compiler.pas`
- `test-asm#src:test/hello.pas`
- `test-asm#src:test/test_asm_entry_global.asm`
- `test-asm#src:test/test_asm_extern.asm`
- `test-asm#src:test/test_asm_hello.asm`
- `test-asm#src:test/test_asm_loop.asm`
- `test-asm#src:test/test_asm_mvp.asm`
- `test-asm#src:test/test_asm_obj.asm`
- `test-asm#src:test/test_asm_so.asm`
- `test-asm#src:test/test_asmcore_aarch64.pas`
- `test-asm#src:test/test_asmcore_arm32.pas`
- `test-asm#src:test/test_asmcore_i386.pas`
- `test-asm#src:test/test_asmcore_riscv32.pas`
- `test-asm#src:test/test_asmcore_x64.pas`
- `test-asm#src:test/test_asmcore_xtensa.pas`
- `test-core#src:compiler/compiler.pas@2`
- `test-core#src:test/crtl_lfs64_aliases_b234.c`
- `test-core#src:test/test_advanced_records_b268.pas`
- `test-core#src:test/test_anonymous_record.pas`
- `test-core#src:test/test_asm_branch.pas`
- `test-core#src:test/test_asm_memr.pas`
- `test-core#src:test/test_asm_sizekw.pas`
- `test-core#src:test/test_byvalue_record_managed_copy.pas`
- `test-core#src:test/test_channel.pas`
- `test-core#src:test/test_dynarray_record_field.pas`
- `test-core#src:test/test_forin_record_enumerator_b355.pas`
- `test-core#src:test/test_getinterface_guid_b257.pas`
- `test-core#src:test/test_nilpy_html_tempfile.npy`
- `test-core#src:test/test_nilpy_module_first_import.npy`
- `test-core#src:test/test_nilpy_raw_string_set.npy`
- `test-core#src:test/test_nilpy_re.npy`
- `test-core#src:test/test_promoint.pas`
- `test-core#src:test/test_promoint_overflow.pas`
- `test-core#src:test/test_ptr_deref_vararg.pas`
- `test-core#src:test/test_record_ctor_expr_tails_b333.pas`
- `test-core#src:test/test_record_rules_ok.pas`
- `test-core#src:test/test_setlength_managed_field.pas`
- `test-core#src:test/test_textfile.pas`
- `test-core#src:test/test_textfile_in_unit.pas`
- `test-core#src:test/test_types_point_methods_b269.pas`
- `test-smoke#src:test/test_mutex.pas`
- `test-threads#src:test/test_async_parallel_compat.pas`
- `test-threads#src:test/test_atomic64.pas`
- `test-threads#src:test/test_atomic_counter.pas`
- `test-threads#src:test/test_condvar.pas`
- `test-threads#src:test/test_critsec_once.pas`
- `test-threads#src:test/test_event.pas`
- `test-threads#src:test/test_mutex.pas`
- `test-threads#src:test/test_palthread.pas`
- `test-threads#src:test/test_parallel_for.pas`
- `test-threads#src:test/test_parallel_for_capture.pas`
- `test-threads#src:test/test_parallel_for_capture_string.pas`
- `test-threads#src:test/test_parallel_for_lang.pas`
- `test-threads#src:test/test_parallel_reduction.pas`
- `test-threads#src:test/test_parallel_writeln_atomic.pas`
- `test-threads#src:test/test_thread_writeln_interleave.pas`
- `test-threads#src:test/test_tthread.pas`
- `test-threads#src:test/test_tthread_final.pas`
- `test-threads#src:test/test_tthread_sync.pas`
- `test-threads#src:test/test_tthread_terminate.pas`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*

---

## Triage (2026-08-01, `claude@borg`, Track T face 2) — single suspect, not a harness event

The stub guesses "likely a broken build or harness event". **It is not.** The
range is two commits, and only one of them touches code:

```
b93577cd3  fix(A): expression args to a const Variant param work outside NilPy too
bf753c961  chore(progress): resolve bug-a-const-variant-arg-expression-fails-outside-pyexprmode
```

`b93577cd3` changes **`compiler/parser.inc` (+83/-22)** — shared Track A/P
ground, the file every frontend's parse path runs through. A 60-job sweep from a
parser change is the expected blast radius, not a mystery.

`parent_tested` was `ac1dad059df9` (GREEN). So: **bad `25678cbdd57c`, last good
`ac1dad059df9`, one code commit in range.** No bisect needed.

## Why this one is urgent rather than merely red

- It takes out **`test-core#src:compiler/compiler.pas@2`** — the self-host. That
  is the property the whole stable-binary chain rests on, and the one gate the
  fast-forward model does *not* offload.
- Native is the **push bar**. Dev agents land on a 15s `quick` tier and rely on
  the watcher's native run as their gate
  (`two-box-protocol.md`). While native is red, every subsequent push is
  building on a broken master and the model's safety net is down.
- 60 jobs across `test-asm`, `test-core` and `test-smoke` — this is not a
  narrow feature break.

## Recommended action

**Revert `b93577cd3` unless a fix is immediate.** Fix-forward is the standing
policy and it is right for narrow reds, but the policy's own limit applies here:
do not leave master knowingly broken, and a core-job red is a revert candidate.
The commit is self-contained (parser.inc plus a new test and a Makefile line),
so a revert is clean and the feature can return with the cascade understood.

Owning lane is **A** (or P — `parser.inc` is the shared Pascal-frontend file).
Track T filed and triaged this; T does not fix it.

## Note for the Track T evaluation

This is the fast-forward model's first real test and **the detection worked**:
the change landed, the watcher's native tier caught a 60-job cascade within
minutes, tied to an exact sha, with a two-commit range. That is precisely the
trade the model buys. What it also shows is the other half of the deal — the
window between landing and the callback is a window in which master is broken
for everyone, so the response to a cascade has to be fast, and "revert" needs to
stay a normal move rather than an admission of failure.

---

## CORRECTION (2026-08-01) — already reverted before this ticket existed

The triage above recommends reverting `b93577cd3`. **It had already been
reverted**, ~25 minutes before that recommendation was written. Timeline (UTC):

| time | event |
|---|---|
| 02:50:11 | `b93577cd3` lands |
| **02:52:11** | **`610936615` reverts it** — dev agent's own testing, `test_promoint` |
| 02:56:05 | `e8e08bb46` documents the revert |
| 02:56:29 | watcher publishes the 60-job cascade for `25678cbdd57c` |
| 02:56:33 | watcher auto-files this ticket |
| 03:2x | Track T triage added — recommending an action already taken |

Resolved by `610936615`. No further action; the cascade should close on the next
native run over current HEAD.

### Three conclusions, and one is about me

1. **The dev agent's own loop beat the watcher by ~4 minutes.** It caught the
   break via `test_promoint` and reverted before Track T reported anything. For
   *this* class of break — broad, immediate, caught by a test the author already
   runs — local testing is still faster than the callback. Track T's value is
   the breadth the author cannot run, not latency on the obvious.
2. **The watcher filed an urgent-looking cascade for an already-fixed sha.** It
   tests a sha; by the time it reports, master has moved. Nothing is wrong with
   the report — `25678cbdd57c` really was broken — but the *ticket* reads as a
   live emergency. Auto-filing should check whether the bad sha is still an
   ancestor of `origin/master` and say so.
3. **I compounded it.** `two-box-protocol.md` says, in my own words: *"Before
   acting on any callback: re-check it at current HEAD. It may already be fixed,
   or moved."* I triaged the cascade, pinned the culprit, raised it to urgent at
   prio 90 and recommended a revert — without once checking whether master had
   already moved. The rule exists precisely because this is easy to get wrong,
   and it was written the same day it was ignored.

## Log
- 2026-08-01 — resolved, commit 610936615.
