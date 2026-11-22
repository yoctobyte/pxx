---
slug: bug-c-a-bit-field-after-a-function-pointer-or-inline-struct-member-overlays-it
track: C
prio: 60
type: bug
status: done
created: 2026-11-22
found-by: claude-pxx (building micropython v1.24.1's unix port with pxx)
tags: [cfront, bitfield, layout, abi]
blocked-by: []
summary: "DONE 2026-11-22: ParseCStructInto moved its bit cursor (bitPos) past plain members only. A function-pointer member (or an array of them) and an inline or anonymous struct member advanced curOff and left bitPos behind, so the next bit-field went back to bit 0 and overlaid the member, and later members followed it: `struct { void (*a)(void); unsigned b:1; char tail; }` was 8 bytes with tail at 1 (gcc: 16, 9). micropython's mp_stream_p_t (`read, write, ioctl` then `is_text : 1`) made every stream read jump to read+1, which accounted for about 40 of its failing tests. The three paths now re-seat bitPos like the plain one. Test c_bfafp26 (x86-64, i386, aarch64)."
---

# A bit-field after a function-pointer or inline-struct member overlays it

This changes the ABI of any such struct shared with gcc-built code, so the old
layout was wrong at the object boundary too, not only inside pxx.

Shapes checked against gcc (size, offset of a trailing char):

| members before `unsigned b : 1` | gcc | pxx before |
|---|---|---|
| `void (*a)(void);` | 16 9 | 8 1 |
| `struct { int p, q; } s;` | 12 9 | 4 1 |
| `struct { int p, q; };` (anonymous) | 12 9 | 4 1 |
| `void (*fa[2])(void);` | 24 17 | 8 1 |
| `char c; void (*a)(void);` | 24 17 | 8 2 |
| `unsigned x : 3; void (*a)(void);` | 24 17 | 8 1 |
| `struct In s;` (named tag) | 12 9 | 12 9 (this path was already right) |
| `int arr[3];` | 16 13 | 16 13 |

After the fix all of them match. test/c_bitfield_after_fnptr_member.c also
writes and reads every member, to catch overlap that leaves the size right.
