---
track: C
tags: [cfront, structs, limits, rump, netbsd]
prio: 70
type: bug
blocked-by: []
summary: "Past 2048 record slots (MAX_UCLASS, shared by Pascal classes and every C struct/union tag, named, anonymous or forward), later C structs fell back to opaque: \"no member named 'p_list'\", \"INCOMPLETE type\", a stray tqe_next, \"expected ':'\" in a ?: call. NetBSD files reach 4400-4900 tags (syscallargs.h). 19 rump files. MAX_UCLASS is now 16384. rump-pxx g35, g38; found by the kernel session."
status: done
owner: pxx2
---

# More than 2048 struct tags

defs.inc MAX_UCLASS 2048 -> 16384 (about 6 MB more static tables; the RTTI
interface id mask has 24 bits, so no packing limit). The opaque fallback at the
table's end stays for anything larger.

Test: test/c_many_struct_tags.c (3100 tagged structs, then the rump shapes)
against gcc, x86-64 and i386.
