---
track: C
tags: [c, asm, object, aliases, rump, netbsd, silent-miscompile]
prio: 10
type: feature
blocked-by: []
summary: "File-scope asm(...) was skipped token by token, so NetBSD's __strong_alias/__weak_alias (~1000 in rump) produced no symbol, and any code written there vanished silently (rump gap S3). Now .globl/.weak + `a = b` / .set / .equ become GLOBAL/WEAK alias symbols in x86-64 objects, .ident/.gnu.warning string sections are dropped, and anything else is refused by name."
status: done
owner: claude-dupwt
---

# File-scope asm: symbol aliases

rump's silent gap S3 (Rainyday docs/rump-pxx/README.md). NetBSD's
`sys/cdefs_elf.h` spells aliases as file-scope asm:

    #define __strong_alias(alias,sym) __asm(".global " #alias "\n" #alias " = " #sym);
    #define __weak_alias(alias,sym)   __asm(".weak "   #alias "\n" #alias " = " #sym);

There are 317 + 681 of them in the rump sources: `ufetch_long` = `ufetch_64`,
`mutex_spin_exit`, `fd_putsock`, `delay`, and so on. There are also 375
`__KERNEL_RCSID`s, which are `.pushsection .ident` strings. pxx's top-level
loop skipped `asm` like an attribute keyword and then skipped every token
after it, so no alias symbol existed. Code in a file-scope asm (the s03
repro) disappeared the same way.

## What is handled

`CParseFileScopeAsm` (pass 1) reads the template:
- `.globl`/`.global`/`.weak` binds;
- `a = b`, `.set a, b`, `.equ a, b` aliases;
- `.hidden`/`.type`/`.size`/`.ident`, ignored. An ifunc `.type` is refused.
- `.pushsection` blocks of `.ident`, `.comment`, `.gnu.warning`,
  `.copyright` and `.note`, holding only `.ascii`/`.asciz`/`.string`. They
  are dropped: they are comments and linker warnings.

Anything else is refused by name: a label, an instruction, data, or another
section.

The x86-64 object writer appends one symbol per alias, after every other
symbol: GLOBAL or WEAK, FUNC or OBJECT, at the target's section, offset and
size. It refuses an alias with no bind (local), an alias whose target is not
defined in the file, and a name the file also defines. When the file also
calls or reads the alias by name (rump's `locks.c`, `vm.c`), that import's
symbol slot becomes the alias definition, so its relocations bind to it.
A `;` or `#` inside a quoted `.ascii` string is text, not a separator or a
comment (libprop's `__warn_references` messages).

## Proof

`test/c_file_scope_asm_alias.c` covers strong and weak function aliases, a
data alias written through the alias, the RCSID and warning strings, and a
weak alias overridden by a strong definition in the gcc main. Its `nm` and
output match gcc for hosted and `--freestanding` objects; `-O2` was checked
by hand. `test/c_file_scope_asm_code_refused.c` is the s03 repro, now an
error naming `myfunc:`.

Not done: assembling code or data written in file-scope asm (through the GNU
as front end), and aliases in a program pxx links itself (`--link` /
executables). There the alias is recorded and not emitted, and a use of the
alias name fails at link.
