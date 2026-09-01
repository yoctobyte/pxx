---
slug: bug-a-three-backends-drop-the-field-width-on-a-string-variable
title: "i386, aarch64 and arm32 drop the field width on a string VARIABLE while padding a string LITERAL"
track: A
prio: 55
type: bug
status: open
created: 2026-09-02
found-by: frankA
owner: ""
blocked-by: []
summary: "`Write(s:9)` where s is a ShortString or AnsiString VARIABLE emits the write with no padding on i386, aarch64 and arm32; x86-64 and riscv32 pad, and so does FPC. `Write('abcdef':9)` -- the LITERAL -- pads on all five, so the bug is invisible to any test written with a literal. Measured on all five backends against FPC (qemu-aarch64/-arm/-riscv32 are installed on plexus). Char, Integer and Boolean widths are correct everywhere. The three arms simply never read `wid`: aarch64's tyString/tyAnsiString arms are at ir_codegen_aarch64.inc:4516 and 4526, and the tyAnsiString one additionally REUSES `wid` as a Patch32 position, so the fix must rename before it pads. Any cross-target program printing a column-aligned report from string variables comes out ragged and nothing errors."
---

# One construct, two spellings, and only the literal was ever tested

Measured 2026-09-02, one program, five backends, FPC as the oracle:

```pascal
var s: ShortString; a: AnsiString;
s := 'abcdef'; a := 'abcdef';
WriteLn('[', s:9, ']');          { ShortString variable }
WriteLn('[', a:9, ']');          { AnsiString variable }
WriteLn('[', 'abcdef':9, ']');   { literal }
```

| target | `s:9` | `a:9` | `'abcdef':9` | `c:5` `i:5` `b:8` |
| --- | --- | --- | --- | --- |
| x86-64 | `[   abcdef]` | `[   abcdef]` | `[   abcdef]` | correct |
| riscv32 | `[   abcdef]` | `[   abcdef]` | `[   abcdef]` | correct |
| **i386** | `[abcdef]` | `[abcdef]` | `[   abcdef]` | correct |
| **aarch64** | `[abcdef]` | `[abcdef]` | `[   abcdef]` | correct |
| **arm32** | `[abcdef]` | `[abcdef]` | `[   abcdef]` | correct |
| FPC | `[   abcdef]` | `[   abcdef]` | `[   abcdef]` | correct |

The literal arm reads `wid` and pads; the variable arms do not read it at all.
That is why this survived
`bug-a-x86-64-write-ignores-a-field-width-on-a-char`, which swept the same
question for Char and left a test whose string rows all use literals or an
AnsiString on x86-64.

## What the fix has to do

The literal arm knows the length at compile time and emits a constant-length
pad. The variable arms cannot: the pad is `max(0, wid - len)` computed at
runtime, which is the shape x86-64 already has (`ir_codegen.inc`, the
`sub rax, rcx` / jump-over-the-pad sequence, and its AnsiString sibling forty
lines below).

Landmine in the aarch64 file: `ir_codegen_aarch64.inc:4530` assigns
`wid := CodeLen` inside the tyAnsiString arm and patches with it. `wid` is the
field width everywhere else in the same procedure. Rename that to a `pDone`
before adding a pad, or the pad will read a code offset as a column count.

Both of the two x86-64 arms this mirrors carry their own history --
`bug-a-hand-written-literal-short-jumps-span-emitters-that-can-grow` found the
ShortString one jumping eight bytes past its target -- so copy the shape, not
the constants.

## Verification

`qemu-aarch64`, `qemu-arm` and `qemu-riscv32` are on plexus, so all five
backends can be diffed against FPC from one box; the program above is the whole
harness. riscv32 and x86-64 are the positive controls: they must not move.
