---
prio: 55
track: A
type: bug
status: backlog
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
