---
prio: 55
track: A
type: bug
status: done
summary: "Write(p^) for `p: ^string[10]` prints hundreds of bytes of garbage on x86-64 with NO FLAG, on the PINNED compiler -- so it predates phase 2 and is not byte-prefix fallout. Every assertion in test_shortstring_through_a_pointer passes on x86-64 (21/21) while this row is wrong, which is why it is PRINTED and not asserted: a Boolean cannot see 'right length, wrong data address'. aarch64, arm32 and riscv32 are all correct here and match the FPC oracle byte-for-byte, so x86-64 is the outlier and is the only backend the new test could not be wired for."
---

# Write of a frozen string through a typed pointer prints garbage (x86-64)

```pascal
type TS10 = string[10]; PS = ^TS10;
var s: TS10; p: PS;
begin
  s := 'hello'; p := @s;
  Write(s);    { <hello>  correct }
  Write(p^);   { <  ...hundreds of bytes of stack and heap...  > }
end.
```

**Reproduces on `stable_linux_amd64/default/pinned`, default mode, no
`-dPXX_SHORTSTRING`.** So it is not phase-2 fallout and not a prefix-width bug;
it is the pre-existing state of the deref write path on the reference backend.

FPC 3.2.2 prints `<hello>` for both. aarch64, arm32 and riscv32 print `<hello>`
for both and match the oracle byte-for-byte.

## Why it survived until now

The write path reads the length and the data ADDRESS off the prefix separately,
so it can get one right and the other wrong — it prints a plausible-looking
count of bytes from the wrong place. **No Boolean assertion can observe that.**
`test_shortstring_through_a_pointer.pas` passes all 21 of its assertions on
x86-64 while this row is visibly broken, which is exactly why that file prints
the write rows and compares them as text instead of asserting them.

## What it blocks

The new reader matrix is wired for aarch64, arm32 and riscv32 and **not for
x86-64**, purely because of this row. Fixing it lets the host row be added, and
the host is the backend every other lane measures on.

[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]

## RESOLVED — the write path was the third reader, and it needed TWO fixes

`Length(p^)`, `p^ = 'hello'`, `p^[1]` and `t := p^` were all correct in the same
binary while `Write(p^)` was not, because those four resolve the pointee through
PtrElemTk and the writer instead consumes the operand node as a bare ADDRESS.

1. x86-64: the AN_DEREF rvalue arm retags its address node with the frozen kind
   (correct, and the comparison path depends on it — removing it made
   `p^ = 'hello'` answer FALSE). But on an IR_LOAD_SYM that tag also decides how
   the operand is COMPUTED: codegen reads a frozen kind on a load as "this
   symbol IS a frozen string, take its address", turning `load p` into `lea p`
   and handing the writer the address of the POINTER VARIABLE — a huge length
   read out of the pointer value, then NULs. The write path now asks
   IRLowerAddress directly, which for AN_DEREF already yields the pointer load.

2. That alone fixed x86-64 and left aarch64, arm32, riscv32 and xtensa printing
   an EMPTY field under -dPXX_SHORTSTRING: those backends pick between
   PXXWriteFrozenW and its one-byte sibling PXXWriteFrozenBW via IRStrTkOf,
   which only consulted IRFrozenKindOfAddr when the node was ALREADY tagged
   frozen — so an honest pointer load fell through to the 8-byte helper.
   IRStrTkOf now resolves a tyPointer node too, taking the answer only when it
   comes back frozen. One substitution, all seven backends, no per-backend edit.

Verified against the FPC 3.2.2 oracle in both modes, and the wired test matches
its expected block byte-for-byte on all 12 configurations (4 native modes;
x86-64, aarch64, arm32, riscv32, xtensa x 2 modes). New `drfw` row. gate quick
GREEN, FPC seed canary PASS.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 3b0f71ccd.
