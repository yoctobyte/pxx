---
track: C
tags: [cfront, static-init, freestanding, rump, netbsd]
prio: 50
type: bug
blocked-by: []
summary: "--freestanding .data initialisers refused `&arr[sizeof(arr)/sizeof(arr[0])]` (NetBSD's __arraycount end pointer in every struct domain, 7 files; kind 35), `(const void *)(const uint8_t[]){..}` (nist_hash_drbg.c; kind 39) and `&(const struct hvec){..}` in an array of pointers (same file; kind 35). rump-pxx g36, g37."
status: done
owner: pxx2
---

# __arraycount end pointers and array compound literals in .data

ir.inc: CBakeAddrOf takes any constant subscript (CBakeIntValue), not only a
literal. CBakeAddrValue's AN_COMPOUND_LITERAL arm moves the literal's hidden
temp to .data and folds its init chain (CBakeInitChain; the zero-fill needs no
bytes), and its value is the temp's address; AN_ADDR of a compound literal is the
same address.

Test: test/c_static_init_fold_{data,main}.c (row c_sifold26), the object
linked by gcc against gcc's own.
