---
slug: feature-xtensa-freestanding-objects-carry-the-idf-application-runtime
track: C
prio: 30
type: feature
status: backlog
created: 2026-11-16
found-by: pxx (Gibux seat) at f2629553ba, gibux docs/tickets/0004
tags: [esp, xtensa, size, freestanding]
blocked-by: []
summary: "`--target=xtensa --emit-obj --freestanding` objects still carry an ESP-IDF application runtime, about 7 KB each (app_main, PXXIdfStdWrite, PXXSysWrite, __pxx_atexit_run, PXXNilRef 1.8 KB); x86-64 freestanding objects carry 1.4 KB. Gibux lib/string.c: 12 KB pxx vs 0.6 KB xtensa gcc -Os. Not blocking: Gibux has no ESP32 port."
---
