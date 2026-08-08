---
prio: 70
status: done
owner: claude-N
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_for_two_names_over_a_variant.npy red at b51f4eeffbf9 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-07T05:50:35Z
- **Test source:** test/test_nilpy_for_two_names_over_a_variant.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_for_two_names_over_a_variant.npy'` at b51f4eeffbf9073bb388d9b709c88af7081a9ea0

## Range
bad `b51f4eeffbf9`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3058844/test_nilpy_for2var26  [code=1387854B  data=33352B  bss=11492B  procs=1194]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## RESOLVED 2026-08-08 — the EXPECTATION was unrepresentable, not the compiler

The program is right. `tools/pydiff.py` agrees with CPython on all 22 lines.

The Makefile expectation could never match, no matter what the compiler emitted:

```make
test "$$(...)" = "$$(printf '...\n['ab', 'cd']\nTypeError')"
```

The expected output contains Python's repr of a list of STRINGS, and a single
quote inside a SINGLE-QUOTED `printf` ends the quote — so the shell built
`[ab, cd]` and compared that. Extracting both operands from testmgr's own
generated script and running each confirms it: actual `"['ab', 'cd']"`,
expected `'[ab, cd]'`.

It went red when the compiler started printing the CORRECT repr; the test had
been encoding the old wrong one by accident.

Converted to a `.expected` + `diff -u`, which is quoting-proof. A scan of the
whole Makefile found this was the ONLY line with the bug — every other
expectation containing a quote escapes it as `'"'"'`.

`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_for_two_names_over_a_variant.npy'` GREEN.
- 2026-08-08 — resolved, commit ed6e77bbf.
