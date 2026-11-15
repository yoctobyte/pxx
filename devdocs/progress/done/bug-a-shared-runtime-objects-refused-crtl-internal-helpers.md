---
slug: bug-a-shared-runtime-objects-refused-crtl-internal-helpers
track: A
prio: 70
type: bug
status: done
created: 2026-11-15
found-by: pixx-cc (dropbear_pxx.py default build RED on 1f87a71427)
tags: [emit-obj, shared-runtime]
blocked-by: []
summary: "Under --shared-runtime a C object leaves crtl's bodies out on purpose, so assert's __pxx_assert_fail and __builtin_popcount's __pxx_builtin_popcount32 are undefined until the runtime object supplies them at --link. The import choke point in symtab.inc refuses every unbodied `__pxx_*` (no shared library exports one), so dropbear's common-channel, ecc, kex-pqhybrid, rsa and mlkem768 failed to compile. Exempt when SharedRuntime and EmitObjMode. Test: c_shared_runtime_part.c now uses assert and __builtin_popcount. dropbear_pxx.py default (shared runtime): 38 rows, 0 failed."
---

# Shared-runtime objects refused crtl's internal helpers
