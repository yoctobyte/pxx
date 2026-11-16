---
slug: bug-c-a-qualifier-after-a-struct-typedef-body-hid-the-name
track: C
prio: 50
type: bug
status: done
created: 2026-11-16
found-by: pxx (Gibux seat), rump-pxx g06 (NetBSD sys/module.h modinfo_t)
tags: [cfront, declarators]
blocked-by: []
summary: "`typedef struct mi {..} const mi_t;` -- a const/volatile between the body (or tag) and the name stopped ParseCTypedef reading the name, so mi_t was never a type. Both aggregate arms now skip qualifiers there. Test: c_dcls."
---
