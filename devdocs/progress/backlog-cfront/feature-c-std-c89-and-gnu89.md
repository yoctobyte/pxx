---
slug: feature-c-std-c89-and-gnu89
track: C
prio: 15
type: feature
status: backlog
owner: unassigned
created: 2026-11-28
found-by: pxx2 (libinput 1.31.1's test-build-std-gnuc90; pixx-cc asked for it on record)
tags: [cfront, dialect]
summary: "pxx refuses -std=c89/c90/gnu89/gnu90/iso9899:1990 ('pxx C is C99 to C23'). libinput builds one test program with -std=gnu89 to check that its public header still compiles as C90. It is the one libinput unit of 91 that fails. Accepting it means more than a flag: implicit int and implicit function declarations as C90 allows them, gnu89 inline semantics (a plain `inline` definition is an external definition, the opposite of C99), no // comments under strict c89, and no mixed declarations or for-loop declarations under -pedantic. Low priority: test programs and very old code only."
---

# -std=c89 and -std=gnu89

Seen as: `unsupported option: -std=gnu89 (pxx C is C99 to C23:
-std=c99/c11/c17/c23 and their gnu forms are accepted)`. The refusal is
honest and stays until this is done.

Reading -std=gnu89 as gnu99 would be wrong in one place that matters:
`inline`. Under gnu89 a plain `inline` function is an external definition
(extern inline is the inline-only one); C99 has it the other way round. A
silent mapping would change which unit defines a symbol.
