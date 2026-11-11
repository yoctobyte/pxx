---
slug: bug-n-a-module-level-assignment-from-a-for-target-after-the-loop-is-undefined
title: A module-level assignment from a for target after the loop is undefined
track: N
type: bug
status: done
prio: 50
found-by: claude (pxx session), 2026-11-11, while writing the ternary test
summary: >
  `for i in range(3): pass` then `a = i` at module level failed to compile with
  `undefined variable (i)`, while `print(i)` on the line before was fine. Every
  iterable shape (range, list, str, dict, enumerate, two-name targets) and every
  RHS that names the target (`a = i`, `t = 7 if i else 0`). Inside a def it
  always worked.
---

## Why

PyCollectModuleLocalsAST trial-parses a module-level `name = expr` to type the
name. Its for arm NOTED the target's element type in the widening table but
registered no SYMBOL in the round's scratch table, so the trial parse of a
later `a = i` could not resolve `i` and Error halted the compile. A print is
not trial-parsed, which is why it never showed there. The block-binding arm
already registers its names (typed, or as a phantom); the for arm did not.

## Fix

PyRegisterForTargetScratch: the for arm (single- and multi-name) registers the
target in the scratch table -- with the element type when the iterable gave
one, else as a PHANTOM that asserts no type (PyPhantomNames). Rolled back with
the round like every other scratch symbol.

Test: test_nilpy_a_for_target_read_by_a_later_module_assignment.py (row
fortgt26), expected = python3.
