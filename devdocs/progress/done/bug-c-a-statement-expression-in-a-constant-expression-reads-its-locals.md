---
title: "C: a statement expression in a constant-expression context read its locals as names"
status: done
owner: claude-dupwt
prio: 65
area: cfront
---

LinuxKPI's is_power_of_2(n) is `({ __typeof(n) _n = (n); _n != 0 && ... })`.
drm_suballoc.c does `BUILD_BUG_ON(!is_power_of_2(DRM_SUBALLOC_MAX_QUEUES))`, a
typedef'd array dimension. The constant-expression folder (CEvalConstPrimary)
read the `({` as a parenthesised expression and failed on its local:
"undeclared identifier '_n' used as value". Found in the GPU-driver census
(feature-nodisx-linux-gpu-drivers-built-by-pxx).

Fix (cparser.inc): `({ ... })` is never an integer constant expression. The
folder skips it balanced and reports a non-constant, so the caller re-reads
it as a run-time expression (an alloca VLA for a dimension, the way gcc
treats it).

Test row c_stmtcx26 (gcc's output).
