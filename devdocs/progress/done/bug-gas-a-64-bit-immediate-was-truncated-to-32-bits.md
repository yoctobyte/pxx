---
track: C
tags: [gas, assembler, x86-64, silent-miscompile]
prio: 5
type: bug
blocked-by: []
summary: "The GNU as frontend truncated every constant immediate to 32 bits: `mov $0x0101010101010101,%r9` assembled as `mov $0x01010101`, and `mov $0x80000000,%rax` / `mov $0xffffffff,%rax` as sign-extended negatives. NetBSD's memset.S filled with the wrong pattern."
status: done
owner: claude-dupwt
---

# A 64-bit immediate in a .s/.S file was truncated to 32 bits

Found by running NetBSD's memset.S, assembled by pxx, against glibc
([[feature-gas-netbsd-libc-string-and-atomic-sources]]): almost every call
was wrong. Its `mov $0x0101010101010101,%r9` (the byte-splat multiplier)
became `49 c7 c1 01 01 01 01`, i.e. 0x01010101.

## Cause

gasfront.inc evaluates `$expr` to an Int64 and rewrites the operand as text
for the shared AT&T reader, but wrote it with `AIntToStr`, which takes a
32-bit Integer. Every constant above 2^31 lost its top bits before the encoder
saw it. The encoder itself was right: it picks movabs for a value that needs
64 bits. strlen.S escaped only because it spells `movabsq`, which gasfront
handles on its own path. Inline asm was never affected, because its reader
parses the immediate as Int64 directly.

Silent: no error, and a plausible instruction.

## Fix

`AInt64ToStr` for the immediate. The displacement rewrite next to it had the
same call; a displacement must fit 32 bits anyway, so it now refuses a wider
one by name instead of truncating.

`test/gas_frontend_x64_encodings.s` holds the four failing immediates and is
compared byte for byte with GNU as (check_gas_frontend.sh check 5).
