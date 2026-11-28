---
title: "C: gcc __builtin_choose_expr"
status: done
owner: claude-dupwt
prio: 75
area: cfront
---

`__builtin_choose_expr(const, e1, e2)` is e1 when the constant is nonzero,
otherwise e2, and its result has the type of the chosen arm, not the ?:
common type. pxx had no such builtin: "call to undeclared function". That
was 276 compiles in the fifth GPU-driver census
(feature-nodisx-linux-gpu-drivers-built-by-pxx), reached through LinuxKPI and
drm macros.

Fix: ParseCPrimary folds the condition with the constant evaluator, parses
both arms, and keeps the chosen one, as _Generic does. Test row c_choose26
(the arms' sizeof, a struct-valued arm), whose expected output is gcc's.

Follow-up: in a CONSTANT expression (a _Static_assert, an enum, the bitfield
width inside BUILD_BUG_ON_ZERO, as in i915's REG_FIELD_PREP) the folder had no
such builtin, which cost another 41 compiles. CEvalConstPrimary now folds it,
and the arm not chosen is read as a dead ?: arm (CEvalConstDeadArm). Test row
c_voidcond26.
