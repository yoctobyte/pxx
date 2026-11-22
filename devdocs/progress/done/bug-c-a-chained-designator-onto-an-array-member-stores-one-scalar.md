---
slug: bug-c-a-chained-designator-onto-an-array-member-stores-one-scalar
track: C
prio: 55
type: bug
status: done
created: 2026-11-22
found-by: claude-pxx (building micropython v1.24.1's unix port with pxx)
tags: [cfront, initializer, designator]
blocked-by: []
summary: "DONE 2026-11-22: a designator chain ending on an array member (`.d.magic = {\"littlefs\"}`, `.d.magic = \"littlefs\"`, `.d.root = {a, b}`) went to CInitLeaf as a scalar: a char array got the literal's ADDRESS in its first bytes, an int array kept its first element only. Local and static alike; the pin has it too. littlefs v1's lfs1_format writes its superblock this way, so VfsLfs1.mkfs produced a volume mount refused as corrupt (-52), and five vfs_lfs tests failed. CInitDesignatedDescend now hands a chain's last member to CInitWalkMember, the same code a positional or `.d = {...}` initializer uses. Test c_dsgarr26 (x86-64, riscv32; aarch64 by hand). Residual: bug-c-a-designator-ending-in-an-index-into-a-2d-member-stores-a-list-as-one-scalar."
---

# A chained designator onto an array member stores one scalar

```c
lfs1_superblock_t superblock = {
    .off = sizeof(superdir.d),
    .d.type = LFS1_TYPE_SUPERBLOCK,
    .d.magic = {"littlefs"},
    .d.root = {lfs1->root[0], lfs1->root[1]},
};
```

pxx wrote `28 00 00 00 00 00 00 00` where the magic goes. With the fix, the
harness's lfs1 image (format onto a 30-block RAM disk) is byte-identical to
gcc's, and mount, write and read work.
