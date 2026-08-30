---
prio: 70
track: P
status: done
owner: frankwasm
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_str_of_unsigned.pas red at 6d68643f9799 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T19:09:55Z
- **Test source:** test/test_str_of_unsigned.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_str_of_unsigned.pas'` at 6d68643f9799d4e0311e91bcbb139625c3e437a3

## Range
> **The named sha `6d68643f9799` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `6d68643f9799`, last good `1d8db8667267`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1521107/test_strunsigned26  [code=147224B  data=7212B  bss=55396B  procs=464]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Diagnosis and fix (frankwasm, at HEAD): NOT a regression — collateral from a replace keyed on the COUNT

All three tests are correct and unchanged. `89e58402a` added canary checks 24-27
and bumped `test-quick`'s `qc_nilpy26` expectation from `total ok 23 / 23` to
`27 / 27` — correctly. The same replace also hit three `test-core` recipes that
legitimately score 23/23, because **`total ok N / N` is not a unique string in
the Makefile**: seven recipes across four tiers share these totals, so a replace
keyed on the count matched by VALUE where the author meant to match by IDENTITY.

Measured at fixedpoint `bb3a768b89a2`, unmodified sources:

```
test/test_str_of_unsigned.pas                  total ok 23 / 23
test/test_val_radix_and_optional_code.pas      total ok 23 / 23
test/test_rtl_fpc_compat_helpers.pas           total ok 23 / 23
test/quick_canary_nilpy.npy                    total ok 27 / 27
```

`gate.sh quick` was run on `89e58402a` and was GREEN — correctly, and it could
not have been otherwise: **quick runs `test-quick` and not `test-core`, so the
one tier that validated the edit is the one tier containing none of the
collateral.** A `sed` spans the whole 16k-line file; a gate spans one recipe.

Fixed by reverting the three `test-core` lines to `23 / 23` and leaving
`qc_nilpy26` at `27 / 27`, plus a comment at the canary line naming the hazard
for the next person who adds checks there. No compiler change.
- 2026-08-30 — resolved, commit 8983444a8.
