---
slug: feature-c-toybox-binary-is-13-mb
track: C
prio: 30
type: feature
status: open
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
summary: "The pxx-linked toybox is ~13 MB against gcc's 475 KB. Not investigated (debug data? unpruned sections despite --function-sections? code size)."
---

# toybox size

Measure section sizes first.
