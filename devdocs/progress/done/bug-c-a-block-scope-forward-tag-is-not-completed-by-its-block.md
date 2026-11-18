---
track: C
tags: [cfront, structs, scope, rump, netbsd]
prio: 50
type: bug
blocked-by: []
summary: "A tag first named inside a block (`struct pend_entry *slh_first` in a block-scope struct) was forwarded at file scope, so the block's later `struct pend_entry {..}` made a second type and the pointer stayed INCOMPLETE (NetBSD kern_module.c). C 6.7.2.3: the reference declares the tag in that block. rump-pxx g39."
status: done
owner: pxx2
---

# A block-scope forward tag

FindOrForwardCTag: with no visible binding inside a block, declare the tag in
the block (CDefineCTag), as a definition there would.

Test: test/c_many_struct_tags.c (pend()) against gcc.
