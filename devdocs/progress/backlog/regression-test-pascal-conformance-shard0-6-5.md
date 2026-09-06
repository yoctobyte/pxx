---
prio: 70
track: P
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 0/6`. The job's own `src` (`tools/run_pascal_conformance.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 19 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard0/6 at ef03a6282980 in step 1/1, `tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 0/6` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T00:53:02Z
- **Test source:** tools/run_pascal_conformance.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/run_pascal_conformance.sh`.
  ```
  tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 0/6
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard0/6'` at ef03a6282980142702466c3688817b7bd90f738e

## Range
> **The named sha `ef03a6282980` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `ef03a6282980`, last good `3b13f585f5f4`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ting from specialize of another generic
SKIP tgeneric21.pp — gap: accepts-invalid — nested generic-in-generic declaration — semantics unverified, real gap (see bug-pascal-missing-diagnostics-fail-tests triage 2026-07-11)
FAIL tgenfunc13.pp — %FAIL test compiled (must be rejected)
SKIP tgenfunc19.pp — gap: generic global function + class helper method resolution via specialize
SKIP tgenfunc5.pp — wontfix: parses and runs since the generic-method work; the ROW calls an instance method on a never-Created object and pxx raises nil-reference 216 where fpc runs it. Pre-existing and unrelated to generics (an ordinary non-generic method on a nil receiver does the same on pin v403). Adding one `t := TTest.Create` makes it exit 0.
SKIP tinterface4.pp — wontfix: needs FPC's `variants` unit and FPC's IInterface/NewInstance refcount internals
SKIP tmoperator2.pp — gap: record Initialize/Finalize management operators with managed fields
SKIP tmoperator8.pp — gap: management operators AddRef/Copy/Initialize/Finalize on records
SKIP tover1.pp — gap: `widestring` is an ALIAS of `ansistring` unless {$define PXX_WIDE_PAYLOAD}, so its two string overloads are one type declared twice. PASSES under that define (measured 2026-09-05) — the overload key itself now carries the element WIDTH. Retiring the gate is chore-a-decide-whether-widestring-can-come-out-from-behind-pxx-wide-payload
SKIP tprocvar3.pp — gap: delphi-mode procvar of object, @-less proc assignment, codepointer method addresses
SKIP tstring11.pp — gap: an open `array of WideChar` / `array of AnsiChar` argument binding a UnicodeString/RawByteString parameter. The overload KEY is no longer the blocker — under {$define PXX_WIDE_PAYLOAD} the two Test1 candidates are distinct and the refusal moves to the open-array conversion at line 42; without it they are one type (same alias gate as tover1)
test-pascal-conformance: 67 pass, 1 fail, 19 skip, 5 auto-gated (of 92)
test-pascal-conformance: FAILURES: tgenfunc13.pp(accepted-invalid)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## TRIAGE 2026-09-06 (frank-coordinator) — ALREADY DISPOSITIONED AT HEAD; do not claim, it self-clears

**The failing row is `FAIL tgenfunc13.pp — %FAIL test compiled (must be rejected)`**, visible
in the log tail above. It was answered **before the watcher reported it** and the answer is
already on origin.

```
tested sha      ef03a6282980
disposition     a892cd589   test/pascal-conformance/pxx.skip  (tgenfunc13 skip line)
merge-base --is-ancestor a892cd589 ef03a6282980   ->  FALSE
```

**The skip landed AFTER the sha that was tested**, so the tested tree genuinely lacked it
and the RED is correct about that tree and stale about HEAD. **Nothing to implement. The
next full tier on seven clears this row by itself** — a regression clears when a later run
on that host passes the job, and no agent action is on that path.

**Re-laned T -> P.** The Track T banner is right that the failing step named no owner; the
row is a Pascal conformance disposition, so the lane is P for accuracy. That is bookkeeping,
not an invitation.

### Why it went red is more interesting than that it did, and it is already written up

`tgenfunc13` was **REJECTED at pin v404 and is ACCEPTED at HEAD**, which reads exactly like a
behaviour regression on a `{ %fail }` row and is the opposite. **The pin refused it because
the generic-method header did not parse at all**, so the row was passing by accident rather
than by rule; `1364d9542` made the header parse and removed the accident.

> **A `%FAIL` row asserts that the compile is REFUSED and never WHICH refusal, so any
> unimplemented construct anywhere in the file satisfies it — and such a row goes RED the
> moment the unrelated gap closes. The red is a signal that a FEATURE LANDED.**

The skip line is not a citation of a sibling row: the shared premise was **measured** —
constraints on generic METHODS are parsed and DROPPED, so a contradictory pair (declared
`<T: class>`, implemented `<T: record>`, specialized with `Integer`, which is neither)
compiles and runs, and the repeat FPC forbids therefore produces no wrong answer and refuses
no legal code. It carries a **re-measure trigger**: *the repeated and contradictory forms
stop being equivalent the moment either side is enforced, and this row becomes a real FAIL
again if constraint checking is ever added.*

Full context in `devdocs/dev/debugging-playbook.md`, `## "IT PASSED AT THE PIN" AND "IT
PASSED FOR THE REASON IT NAMES" ARE DIFFERENT CLAIMS`, and in the same pass that removed two
other skips rather than adding any (`tgenfunc9`, `tgenfunc3`) — families now `tgeneric*`
75/0 and `tgenfunc*` 6/0.

**CORRECTION, same commit-hour, by the author of the sentence above.** I first wrote *"the
second auto-filed red in six hours whose answer was already on origin."* **That is not
established and I have not checked it.** The other four auto-filed reds tonight
(`test-fgl`, `test-core#fpc_compat_batch2`, and the two NilPy star-args rows) were all filed
BEFORE their fixes landed, so they were live when written. **This is the first one I have
measured with that shape**, and a count I did not take does not become true by sitting next
to one I did.

The rule stands on this instance and on the banner's own existence, and does not need the
count: the watcher tags a callback to the sha it TESTED and says so itself — *"origin/master
has advanced 19 commit(s) since this sha — re-verify at current HEAD before acting."*
**That banner is the instrument; read it before the log tail.** Here the log tail was the
compelling part and the banner was the true one, and the check it asks for is one
`merge-base --is-ancestor`.

## Log
- 2026-09-06 — the seven watcher saw `test-pascal-conformance#shard0/6` GREEN at 63cb15752786 (tier full) and did NOT close this: this is a repeat stub (`regression-test-pascal-conformance-shard0-6-5`, not `regression-test-pascal-conformance-shard0-6`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
