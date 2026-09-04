---
prio: 70
track: T
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 4 is `tools/expect_same.sh dsspal26/wasm32 "$(tools/run_target.sh wasm32 /tmp/dsspal.wasm)" "DYNSLOTSTORE OK"`. The job's own `src` (`test/test_cross_dynarray_slot_store.pas`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-core#src:test/test_cross_dynarray_slot_store.pas@2 at 8860639aa3ee in step 2/4, `tools/expect_same.sh dsspal26/wasm32 "$(tools/run_target.sh wasm32 /tmp/dsspal.wasm)" "DYNSLOTSTORE OK"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T14:43:13Z
- **Test source:** test/test_cross_dynarray_slot_store.pas tools/expect_same.sh +2
- **Failing step:** line 2 of 4 of the job's recipe; it names `tools/expect_same.sh tools/run_target.sh`.
  ```
  tools/expect_same.sh dsspal26/wasm32 "$(tools/run_target.sh wasm32 /tmp/dsspal.wasm)" "DYNSLOTSTORE OK"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_cross_dynarray_slot_store.pas@2'` at 8860639aa3ee39f7dbf85d44204643ef368b092e

## Range
bad `8860639aa3ee`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
ok: /tmp/testmgr-scratch-1536290/dsspal.wasm  [code=3499B  data=3360B  bss=1090908B  procs=137]
wasmtime not found (looked on PATH and in ~/.local/bin)
expect_same: MISMATCH [dsspal26/wasm32]
--- expected
+++ actual
@@ -1 +1 @@
-DYNSLOTSTORE OK
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

## Not a regression — the host had no wasmtime (frankA, 2026-09-04)

**Six auto-filed tickets, six different test names, six different commits, ONE
missing binary.** This is one of them. The whole set:
`test-cross-frozen-ptr-narrow`, `-frozen-ptr-in-field`, `-typeinfo-dataref`,
`-dynarray-slot-store`, `-os-entropy-through-the-pal`, `-futex-through-the-pal`.

The log tail of every one of them carries the line
`wasmtime not found (looked on PATH and in ~/.local/bin)` immediately above the
mismatch. `tools/run_target.sh` printed that on **stderr** and exited 2 — but
every Makefile assertion calls it inside `"$(tools/run_target.sh wasm32 ...)"`,
and a command substitution captures stdout and **discards the exit code**. The
comparison therefore ran with the empty string, and the diff reads exactly like
wasm32 emitting nothing:

```
-fld16  T [AB] 2 [AB] [xAB] A
 ...
+
```

Re-measured on a host that HAS wasmtime, at the same tree, all six pass:

```
ENTROPY OK / DYNSLOTSTORE OK / FROZENPTRFIELD OK / FROZENPTRNARROW OK
enums OK, header Integer, header TPoint / fxpal all three modes
```

### What was fixed, and what was not

`tools/run_target.sh` now reports an absent runner on **stdout as well**, as
`RUNNER-ABSENT: <tool> not found, so target '<arch>' was NOT RUN`, for the qemu
arms too. **It still exits nonzero and the row still goes red** — an unrun test
is not a passing test — but the row now names the HOST instead of accusing the
target, and the next auto-filed ticket will carry that sentence in its own log
tail.

What was NOT fixed is the actual gap: **host seven has no wasmtime**, so every
wasm32 row there is unverified. That is a machine, not a tree, and it is not
mine to change.

### The reading that nearly cost more than it did

Four of these were read as four separate defects in four freshly added tests,
because each names its own test and its own commit and nothing in a ticket says
"the other five say this too". The distinguishing observation was free and was
in the ticket already: the fix a50671107 landed 15:41Z and the test went red at
15:56Z, so **the fix was in the tree when the test failed** — which no
compiler-state story explains. Read the log tail above the diff before reading
the diff.
