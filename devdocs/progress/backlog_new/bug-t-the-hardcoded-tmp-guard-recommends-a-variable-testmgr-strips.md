---
track: T
prio: 55
type: bug
blocked-by: []
summary: "tools/testmgr_hardcoded_tmp_devtest.py tells you to read $TESTTMP instead of hardcoding /tmp. But testmgr launches every job through an environment ALLOWLIST, and TESTTMP is in neither ENV_ALLOW nor the ENV_ALLOW_PREFIXES (PXX_ TESTMGR_ LC_ QEMU_), so it does not reach the job at all. Every test that followed the advice falls back to /tmp under testmgr and collides exactly as a hardcoded literal would — guard green, defect intact. Five existing tests are in that state. TESTMGR_TMP is the variable that survives, and testmgr already sets it per run to a pid-keyed dir it creates."
status: new
owner: ""
---

# The hardcoded-/tmp guard recommends a variable testmgr strips

- **Type:** bug (test tooling / the guard's advice) — **Track T**, which owns
  `tools/testmgr_hardcoded_tmp_devtest.py` and `tools/testmgr.py`.
- **Filed:** 2026-08-29 by the wasm lane, on `origin/master` at `6363a4adc`,
  while fixing `regression-tools-devtest-00-2` — whose ticket text also carries
  the wrong variable, inherited from this message.

## What the guard says

```
Read the directory from the environment instead ($TESTTMP, which the sweep
already exports; default /tmp keeps it byte-identical), or add it to
ALLOWED_PATHS with a reason.
```

## Why that does not work under testmgr

`testmgr.py` launches every job as `subprocess.Popen(["sh", "-c", job.script()],
env=job_env_for(job))`, and `job_env()` builds that environment from an
**allowlist**, deliberately — "a job starts from a declared environment", so
that a job cannot get a different answer depending on how the run was launched.

Measured against the source rather than assumed:

| variable | in `ENV_ALLOW` | matches `ENV_ALLOW_PREFIXES` | reaches the job |
| --- | --- | --- | --- |
| `TESTTMP` | no | no | **no** |
| `TESTMGR_TMP` | no | yes (`TESTMGR_`) | **yes** |

`ENV_ALLOW_PREFIXES` is `("PXX_", "TESTMGR_", "LC_", "QEMU_")`. So a compiled
test that reads `$TESTTMP` gets nothing under testmgr and takes its `/tmp`
fallback — the same shared path the guard rejected the literal for. The
allowlist is right; the advice was written against the plain-`make` path, where
the Makefile's `TESTTMP ?= /tmp` + `export TESTTMP` does reach the child.

`TESTMGR_TMP` is already set for exactly this purpose (`os.environ["TESTMGR_TMP"]
= RUN_TMP`, "for tool scripts' own scratch"), where `RUN_TMP` is
`<TESTTMP>/testmgr-scratch-<pid>` and is created before jobs run. It is per-run
and pid-keyed, so it gives the isolation the guard is trying to buy — and it
gives it *automatically*, without the caller having to know to pass
`TESTTMP=$(mktemp -d)`.

## Five tests are already in this state

Each reads `$TESTTMP` and falls back to a shared directory, so under testmgr all
five write a fixed path in `/tmp`:

| file | fallback |
| --- | --- |
| `test/test_read_text_value_cursor.pas` | `/tmp` |
| `test/test_read_text_char.pas` | `/tmp` |
| `test/lib_ioresult_fpc_codes.pas` | `GetTempDir` |
| `test/lib_textreadnumtok.pas` | `GetTempDir` |
| `test/lib_text_seek_rename.pas` | `GetTempDir` |

These are not *defects* — they are what the guard asked for, and under a plain
`make test TESTTMP=$(mktemp -d)` they isolate correctly. They are inert under
testmgr, which is the runner that actually executes concurrently.

**This is why the ticket is p55 and not p20.** The guard's own argument in
`regression-tools-devtest-00-2` is that *a red ratchet is a disabled ratchet*.
A ratchet whose remedy does not remedy anything is the same failure one step
later: it goes green, everyone believes the class is handled, and the collisions
continue. The five compliant tests are the evidence that the advice is followed
faithfully when given.

## Fix

Two parts, and the second is the one that lasts:

1. **The message.** Recommend `$TESTMGR_TMP` first, `$TESTTMP` second, then the
   `/tmp` default — that order works under testmgr *and* under plain `make`, and
   stays byte-identical when neither is set. One example worth inlining, since
   the guard's message is where authors will read it.
2. **Make the guard able to tell the difference.** Right now it checks only for
   an absence of `/tmp` literals, which is why it cannot distinguish a test that
   isolates from one that merely stopped saying `/tmp` out loud. A test that
   reads *only* `TESTTMP` is exactly as collision-prone under testmgr as the
   literal it replaced, and the guard currently calls it clean.

`test/test_nilpy_class_named_like_an_rtl_record.npy` was fixed this way on
2026-08-29 and is the worked example — comment included, so the next author who
copies a sibling copies the right one.

## Verification

Four environment shapes against a pinned build (v392, `60b060bb54a8`), all
byte-identical to `.expected`, with a sentinel planted at the old hardcoded path
to prove the redirect really happens:

* neither variable set → `/tmp`, output unchanged (the byte-identical claim);
* `TESTMGR_TMP` only (the testmgr shape) → redirected, sentinel untouched;
* `TESTTMP` only (the plain-`make` shape) → redirected, sentinel untouched;
* negative control — the *unfixed* test destroys the sentinel, so the check can
  fail.

## Gate

Track T's own, for a tooling change. For the message-only half the guard answers
in about a second with no build (`python3
tools/testmgr_hardcoded_tmp_devtest.py`), plus the four environment shapes above
on any one converted test.
