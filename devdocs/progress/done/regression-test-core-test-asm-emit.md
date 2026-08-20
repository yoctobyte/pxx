---
prio: 70
track: P
status: done
owner: frank1-ACP
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_asm_emit.pas red at 943c706936b3 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T09:25:51Z
- **Test source:** test/test_asm_emit.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_asm_emit.pas'` at 943c706936b329e1777d68892c8e4eb444211ea8

## Range
bad `943c706936b3`, last good `b24bb1474624`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-326413/test_asm_emit26  [code=95698B  data=2800B  bss=9532B  procs=203]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## Triaged and fixed — one cause behind all three

**Cause:** `f09524494` (bug-p-unary-minus-on-an-unsigned-operand-truncates-to-32-bits)
made `-x` yield Int64 for every integer operand. That is FPC's rule for a
negated VARIABLE — and it is NOT FPC's rule for a negated CONSTANT, which is
folded first and typed by its VALUE: the smallest signed type that holds it. So
`-1` is a LongInt under FPC and became an Int64 here, and three tests saw it:

| test | what moved |
| --- | --- |
| test_asm_emit | `-7` in an `array of const` became vtInt64, so the `vtInteger` reader skipped the entry and the `I=-7` line vanished |
| test_integer_longint_overload | `IntToHex(-1, 8)` bound the Int64 overload and printed 16 digits |
| test_strict_overload_width | the `literal` row moved from longint to int64 |

Measured against `fpc -O- -Mobjfpc`, which types every one of these LongInt.

**Fix:** `ParseFactorCore`'s `tkMinus` arm asks `ASTConstIntValue` (new, in
parser.inc) whether the operand is an integer constant expression. If it is, the
AN_NEG node is typed by the folded value — tyInteger when it fits a signed
32-bit, tyInt64 otherwise — and only otherwise does the Int64 widening apply.
The variable rule is untouched: `-b` on a Byte is still Int64.

Nine FPC-verified rows now agree exactly, including the range edges
(`-2147483648` is LongInt, `-2147483649` is Int64), a named constant, and a
constant expression (`-(1+2)`). Pinned in
`test/test_unary_minus_constant_keeps_longint.pas` (13 assertions, FPC's own
answers) alongside the three tests above.
- 2026-08-20 — resolved, commit 584c2703d.
