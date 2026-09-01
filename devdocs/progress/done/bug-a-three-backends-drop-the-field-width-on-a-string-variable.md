---
slug: bug-a-three-backends-drop-the-field-width-on-a-string-variable
title: "i386, aarch64 and arm32 drop the field width on a string VARIABLE while padding a string LITERAL"
track: A
prio: 55
type: bug
status: done
created: 2026-09-02
found-by: frankA
owner: frankA
blocked-by: []
summary: "`Write(s:w)` on a string VARIABLE was wrong on FOUR of five backends, in THREE separate ways, all from the pad rule having five copies. (1) i386, aarch64 and arm32 dropped the width outright while padding a string LITERAL -- they now call PXXWriteFrozenW/PXXWriteStrMW, the portable helpers riscv32 and wasm32 already used. (2) x86-64 tested the nil handle BEFORE the pad, so an empty AnsiString printed nothing where FPC prints spaces. (3) every x86-64 arm emitted ONE unbounded write over a 40-byte spaces buffer, so `WriteLn(s:60)` wrote 19 bytes of adjacent process memory to stdout -- right LENGTH, wrong CONTENT, invisible to any character count; fixed by one chunking EmitPadSpacesFromRax shared by all three x86-64 arms. All five backends now byte-match FPC on six probes. Test test_write_string_field_width_cross.pas, wired native + i386/aarch64/arm32/riscv32, verified to FAIL pre-fix on four targets and to PASS pre-fix on riscv32, which was the one that was already right."
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

## Resolved 2026-09-02 — and it was three defects, not one

The ticket was filed on defect (1) alone. Writing the cross-target test found
the other two, both x86-64-only, both in the arms the first fix had just made
the other four backends stop duplicating.

| # | defect | wrong on | how it was found |
| --- | --- | --- | --- |
| 1 | field width dropped on a string VARIABLE, honoured on a LITERAL | i386, aarch64, arm32 | five-backend FPC diff |
| 2 | empty/nil AnsiString with a width prints nothing | x86-64 only | a row in the new test |
| 3 | width > 40 writes past the spaces buffer | x86-64 only | a row in the new test |

**(3) is the one worth remembering.** `WriteLn(s:60)` for a one-character
string emitted a single `write(fd, spaces, 59)` against a 40-byte buffer, so
the line had exactly the right LENGTH and 19 bytes of the wrong CONTENT —
adjacent process data on stdout. Every length- or column-counting assertion
passes on it. Only a byte compare against FPC sees it, which is why the test
compares bytes and the ticket says so.

## The shape all three share

The pad rule — `max(0, wid - len)`, runtime because the length is — had **five
copies**: three inline in x86-64, one each inline in i386/arm32/aarch64 (which
had none, hence defect 1), and one in `PXXWritePad`, called by riscv32 and
wasm32. The copy that was exercised by every test was right; the others drifted.

Now: the four non-x86-64 backends call the portable helper, and x86-64's three
arms share one `EmitPadSpacesFromRax`. Two implementations instead of six, and
x86-64 keeps its own because `PXXWrite*W` hardcodes fd 1 while x86-64 honours
`CurWriteFd` (`WriteLn(StdErr, ...)`). The other four already hardcoded stdout
in their string arms, so calling the helper changed nothing there — checked
before the change, not assumed.

Not done, and deliberately: folding x86-64 onto the portable helper too. That
needs `PXXWritePad`/`PXXWriteStrMW` to take an fd, which is an RTL signature
change with its own blast radius.

## Log
- 2026-09-02 — resolved, commit 6ae8af59e. Fixes all three defects; the ticket
  was filed on the first of them.
