---
slug: feature-c-asm-register-variables
track: C
prio: 30
type: feature
status: open
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, inline-asm, toybox]
blocked-by: []
summary: "`register long x __asm__(\"r9\")` local register variables are unsupported; seen in syscall wrappers."
---

# C: explicit register variables

Not needed by toybox defconfig; noted while porting.
