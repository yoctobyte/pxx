---
track: A
prio: 60
type: bug
status: done
found: 2026-09-01
found-by: frankC
owner: frankC
summary: "TypeAlign gave every scalar over 4 bytes an 8-byte alignment on EVERY target, so a `double` or `long long` inside a struct was over-aligned on i386, where the SysV psABI caps scalar alignment at 4. Measured against gcc: `struct MIX {int a; double y;}` is sizeof 12 with y at offset 4 under `gcc -m32` and pxx said 16 and 8. Self-consistent inside pxx, so no pxx-only test could see it -- it surfaced as three wrong rows in test-c-abi-mixed-link, where a gcc caller and a pxx callee disagree about where the field IS rather than about how the argument is passed. The function's own comment said `on x86-64 all scalar types are naturally aligned`, which was true and was read as the whole rule by a function every target asks. FIXED by SPLITTING the function: TypeAlign stays natural on every target and answers for STORAGE (a .bss global, a frame slot, a const array in .data); a new TypeFieldAlign caps at 4 on i386 and answers for a MEMBER of an aggregate. Capping TypeAlign itself was the first attempt and was WRONG in the other direction -- it put an `array of Double` const on a mod-4 address and test_const_array_align went red on i386. gcc -m32 has both answers at once: `_Alignof(double)` is 4 and a global `double[4]` still lands on mod 8. Only the C frontend reads TypeFieldAlign today; the other four frontends are [[bug-a-pascal-nilpy-rust-and-zig-over-align-an-8-byte-member-on-i386]]."
---

# An 8-byte scalar is over-aligned inside a struct on i386

```c
struct MIX { int a; double y; };
```

| | sizeof | offsetof(y) |
| --- | --- | --- |
| `gcc -m32` | 12 | 4 |
| `gcc` (x86-64) | 16 | 8 |
| **pxx i386, before** | **16** | **8** |
| pxx i386, after | 12 | 4 |

`TypeAlign` (`symtab.inc`) computed alignment from size alone and returned 8 for
anything above 4 bytes. i386 SysV caps every scalar at 4.

## Why nothing caught it

It is a LAYOUT divergence, not a marshalling one, and pxx agreed with itself:
the field was written and read at offset 8 on both sides of any pxx-only
program. Only a mixed link can see it, and the mixed-link gate that does see it
did not exist until
[[bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee]]
built one — and even then only once i386 passed structs BY VALUE, because a
struct behind a pointer never has its fields read across the boundary.

**So the defect was reachable only after two other things were fixed.** It was
not hidden by a missing test; it was hidden by a second bug standing in front of
it, the same shape as the nil-check and shared-library cases from the same
night.

## The comment is the part worth keeping

> `Returns alignment requirement (power of 2) for type tk.`
> `On x86-64 all scalar types are naturally aligned.`

True, and read as though it were the whole rule, in a function every backend
asks. A per-target fact stated without its scope becomes a global one — the
`the-name-is-not-the-thing` failure in a comment rather than an identifier.

## One name, two alignments

The first fix capped `TypeAlign` and `test-core` caught it: `MISALIGNED G needs
8 @ mod 8 = 4`, `MISALIGNED E needs 8 @ mod 8 = 4` on i386. The function had
nineteen callers doing two different jobs, and the ABI cap is right for one of
them and wrong for the other:

| caller | asks | i386 answer |
| --- | --- | --- |
| `cparser.inc` struct member | required alignment | **4** |
| `symtab.inc` .bss global, frame slot, const array | where to place it | **8** |

gcc holds both at once, measured rather than argued:

```
gcc -m32:  _Alignof(double) == 4        double G[4]  ->  (unsigned long)G % 8 == 0
```

Over-aligning storage is never wrong and on xtensa `l32i` FAULTS on a
misaligned word, so the placement side must stay natural. Under-aligning a
member is wrong the moment a foreign compiler reads the struct.

**Both directions are now asserted on i386, by different gates**:
`test_const_array_align` (in `test-core`) fails if `TypeAlign` is capped, and
`test-c-abi-mixed-link` fails if `TypeFieldAlign` is not. Neither is a positive
control for the other -- they are the two halves of one guard, and the first
fix passed the half that existed.

## Log
- 2026-09-01 — resolved, commit PENDING-COMMIT.
- 2026-09-01 — reopened within the hour: the cap belonged on a member, not on
  storage. Split into TypeAlign / TypeFieldAlign. commit PENDING-COMMIT.
