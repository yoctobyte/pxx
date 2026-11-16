---
slug: bug-c-a-multi-name-typedef-declares-only-its-first-name
track: C
prio: 60
type: bug
status: done
created: 2026-11-15
found-by: rump-pxx g23, re-measured while fixing S10
tags: [cfront, declarators]
blocked-by: []
summary: "`typedef int A, *PA, ARR[3];`, `typedef struct {..} X, *PX;` and `typedef enum {..} E, *PE;` registered only the first name. CSplitDeclarators rewrites the tokens once, from the `typedef`, into one typedef per declarator: the comma becomes `;` and `typedef SPEC'` is inserted after it, so original tokens keep their attribute flags. SPEC' drops an aggregate body; an anonymous one gets a synthetic tag (__pxx_td_anon_N) first so all names share ONE struct. The enum arm now also takes `typedef enum E *PE;`. Test: c_dcls."
---
