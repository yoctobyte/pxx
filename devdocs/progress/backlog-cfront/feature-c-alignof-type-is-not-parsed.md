---
track: C
tags: [c, frontend]
prio: 25
type: feature
blocked-by: []
summary: "`_Alignof(type)` (C11) and GNU `__alignof__(type)` stop with `expected C expression`. sizeof works. Seen while checking struct sockaddr_storage's alignment for dropbear; dropbear itself does not use either."
status: open
owner: unassigned
---

# _Alignof / __alignof__ are not parsed

    int main(void){ return __alignof__(long); }
    pascal26:1: error: expected C expression

The same happens with `_Alignof(struct sockaddr_storage)`. Found 2026-11-13
while checking crtl's new sockaddr_storage against gcc
([[feature-b-crtl-surface-for-dropbear]]). The check was done with an
offsetof-in-a-wrapper-struct instead. Nothing built so far needs it, so this
is not blocking. Real code that uses it: C11 `alignas`/`max_align_t` users,
and allocators that round sizes up to the alignment.
