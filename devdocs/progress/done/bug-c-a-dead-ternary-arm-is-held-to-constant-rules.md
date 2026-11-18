---
track: C
tags: [cfront, constexpr, rump, netbsd]
prio: 45
type: bug
blocked-by: []
summary: "In an integer constant expression, the arm of `c ? a : b` that a constant c did not select was still held to constant rules: NetBSD's ilog2(x), `__builtin_constant_p(x) ? <arith> : fls64(x) - 1`, as an array size was refused (\"'fls64' is a function -- a constant expression cannot call one\"), and a non-constant dead arm would have made the dimension a VLA. rump-pxx g32."
status: done
owner: pxx2
---

# A dead ternary arm in a constant expression

CEvalConstTernary folds the unselected arm through CEvalConstDeadArm, which
allows a call and restores CConstExprSawNonConst. A run-time condition still
holds both arms to the rules.

Test: test/c_rump_small_fold.c (`int t[ilog2(1000)]`) against gcc.
