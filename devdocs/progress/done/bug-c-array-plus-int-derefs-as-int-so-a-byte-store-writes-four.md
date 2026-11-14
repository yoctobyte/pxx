---
track: C
tags: [C, codegen, types, dropbear, aarch64]
prio: 20
type: bug
blocked-by: []
summary: "`*(arr + n)` and `(arr + n)[k]` on an ARRAY took int as the pointee type, so a byte store wrote four bytes, a byte load read four, a short store wrote four and a u64 store wrote only four. CNodePointeeTk's AN_BINOP arm asked CNodeIsPointer, which is false for an array until it decays. It now asks CNodeDecaysToPointer, as the ternary arm already did. In libtomcrypt's portable STORE64H, three bytes were zeroed past the sha512 state. On aarch64 those bytes were dropbear's local `hash_desc`, so dbclient died with RE 216 on every sha512 kex, and the server's nistp384 kex derived wrong keys."
status: done
owner: unassigned
---

# `arr + n` dereferenced as int

Found building dropbear for aarch64 ([[feature-c-dropbear-builds-with-pxx]],
acceptance 5). Two symptoms:

- pxx dbclient → stock sshd died with "Runtime error 216 (nil reference)",
  but only with sntrup761x25519-sha512.
- The pxx server → OpenSSH client with ecdh-sha2-nistp384 failed with "Bad
  packet length" (wrong keys).

## Diagnosis

No aarch64 debugger exists on plexus, so the trail was:

1. `qemu-aarch64 -strace`: no signal, so RE 216 came from an emitted nil
   check (`PXXNilRef`).
2. A binary patch made every `PXXNilRef` copy write x30 to stderr. The
   caller was `hashkeys()` in common-kex.c, calling `hash_desc->process`
   with a NULL `process`.
3. A second patch dumped the frame. `hash_desc` (x29-0x28) held 0x0a000000
   by the second round, and it sits directly after `hs2`
   (`hash_state`, 208 bytes, x29-0xf8).
4. A guard word after a `hash_state`, with sha512 compiled by pxx for
   aarch64: `sha512_done` zeroed three bytes past the state. Instrumenting
   it pinned the statement: `STORE64H(md->sha512.length, md->sha512.buf+120)`.
5. The portable STORE64H is `(y)[0..7] = (unsigned char)...` with
   y = `buf + 120`. Each byte store was four bytes wide, so the last three
   ran past `buf`.

x86-64 has the same bug. libtomcrypt picks the inline-asm bswap STORE64H on
x86-64, which is why dropbear never hit it there.

## Fix

In `CNodePointeeTk` (cparser.inc), the AN_BINOP arm now asks
`CNodeDecaysToPointer` instead of `CNodeIsPointer`. An array operand yields
its element type, as the AN_TERNARY arm already did. Before the fix,
`sizeof(*(lb + 4))` on an `unsigned char lb[8]` was 4 for every spelling:
local, global, `.` and `->` members, through a union, `int + arr`, `arr - 0`.

## Test

`test/c_array_plus_int_deref_width.c`, rows caplusint26 (x86-64) and
caplusint_a64 (aarch64 under qemu). It covers loads and stores through every
array spelling, 1-, 2- and 8-byte elements, a guard after each array, and
libtomcrypt's STORE64H through a union member. The output equals gcc's. The
pinned compiler (v455) gets all seven lines wrong:

- guards corrupted;
- byte loads of -248;
- the u64 store truncated to 1.

## Also seen (not fixed here)

pxx accepted `h.md5` on a union that has no `md5` member and evaluated
`sizeof` of it to 4. gcc refuses it. Filed as
[[bug-c-an-unknown-member-name-compiles-as-int]].
