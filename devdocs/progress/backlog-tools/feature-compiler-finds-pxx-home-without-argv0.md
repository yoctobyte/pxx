---
slug: feature-compiler-finds-pxx-home-without-argv0
track: C
prio: 30
type: feature
status: open
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [tools, toybox]
blocked-by: []
summary: "pixx-f2 note: the compiler finds its lib trees via argv[0] or PXX_HOME read from /proc/self/environ. Reading envp at process start, with /proc/self/exe as a fallback, would work in a chroot/live ISO without /proc mounted the same way."
---

# pxx home discovery

Suggested by the pixx live-ISO work.
