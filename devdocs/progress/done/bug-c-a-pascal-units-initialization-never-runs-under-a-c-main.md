---
slug: bug-c-a-pascal-units-initialization-never-runs-under-a-c-main
title: "A Pascal unit's `initialization` section never ran under a C main"
track: C
type: bug
prio: 40
status: done
owner: claude-dupwt
found: 2026-11-20
found-by: claude-dupwt (while fixing bug-c-crtl-stdin-and-pascal-input-do-not-share-a-peeked-byte)
---

# A Pascal unit's initialization never ran under a C main

## Before

A C program that pulls in a Pascal unit (`#include "u.pas"`, and pxxcio
itself) registered each unit's `initialization` proc in InitProcs[], but
nothing called them. A Pascal program calls them after its constant
initialisers, before the body. C's `main` called only `__pxx_c_main_init`
(file-scope initialisers and constructors). So a unit's `initialization
WriteLn(...)` printed nothing and its variables stayed zero. textfile never
installed its stdin hook either, which is how this was found.

## Now

`__pxx_c_main_init` calls InitProcs[] in order, after the C initialisers and
before the constructors. That is the Pascal order. Executable only, like the
constructors: an --emit-obj/--shared object's init thunk is unchanged. wasm32
has no main init proc, so it is unchanged and not measured.

Row c_pasunit_init26 (test/c_pascal_unit_init_runs.c): the expected output is
"unit init ran / ready=42". latest-97b51d1032 printed "ready=0".

Verified: gate quick GREEN; test-core and test-c-conformance 0 failures.
