---
track: A
tags: [C]
prio: 30
type: bug
blocked-by: []
summary: "A block-scope `RET (*name[])(params) = { f, g };` was refused with \"expected C expression\" (Gibux fs/procfs.c gens[]): the local array-of-function-pointers arm only took a fixed [N]. It now sizes the array from the initializer. The same arm left the tail of a short list (`(*fs[3])(..) = { f }`) as stack garbage; it now zero-fills it as C requires."
status: done
owner: unassigned
---

# A local unsized function-pointer array is refused

Found by Gibux (`fs/procfs.c`, `procfs_add`):

    long (*gens[])(struct inode *, char *, size_t) = { gen_pid_stat, ... };

ParseCDeclType records an unsized `[]` as dimension -1. The local
array-of-function-pointers arm in cparser.inc only ran for a dimension of 0
or more, so the declaration fell through to the plain-local path and failed
with `expected C expression`. The file-scope spelling was already accepted.

## Fix

- The arm now also takes -1. It reads the initializer first and then
  allocates the array with as many elements as the list has. The element
  assignments are built before the symbol exists, so the arm patches the
  array's symbol index into each one afterwards.
- A list shorter than a fixed `[N]` now assigns 0 to the remaining elements.
  Before, they kept whatever the stack held. The pinned compiler prints
  `40 0 0` where gcc prints `40 1 1`.

## Test

test/c_local_unsized_fnptr_array_from_its_initializer.c, run by its Makefile
row against gcc's output in the `.expected` file. It covers:

- the unsized form, with a trailing comma;
- `sizeof` of the unsized array;
- a short list into `[3]`, with `&f`, run on a stack dirtied beforehand.
