---
track: C
tags: [c, asm, object, symbols, rump, netbsd, silent-miscompile]
prio: 10
type: feature
blocked-by: []
summary: "An asm label (`int foo(int) __asm(\"bar\");`, NetBSD's __RENAME; `long v asm(\"sym\");`) was skipped, so the symbol kept its C name (rump gap S4). On a variable, the label ended up in the top-level skip. Now a defined function or global gets the label as its symbol name in x86-64 objects, and an import is linked by it everywhere (ExternalLinkName)."
status: done
owner: claude-dupwt
---

# Asm labels rename the symbol

rump's silent gap S4 (Rainyday docs/rump-pxx/README.md). `int foo(int)
__asm("bar");` means "foo is called bar at link time". It is NetBSD's
`__RENAME`, and rump's `kern_tc.c` has `time_t time_second_legacy
asm("time_second");`. pxx dropped both:
- On a prototype, the label went with the tail skip up to the `;`.
- On a variable, the declaration parser stopped at `asm` and the top level
  skipped the rest.

The object then defined or imported `foo` and `time_second_legacy`. The link
failed at best, or bound to something else.

## Fix

- One rename list, C name to link name (`CAsmLbl*`). The prototype tail skip
  records the label. A file-scope `asm(` whose previous token is an
  identifier is the label of the variable just declared; it must end the
  declaration, so an initialiser after it is refused by name.
- `ExternalLinkName` consults it, so a renamed import is called by its label
  in objects and in programs pxx links.
- The x86-64 object writer renames defined functions and globals in place
  (`ObjApplyAsmLabels`) before any symbol name is measured.

Found in the same rump pass: five files define a file-scope alias and also
use it by name (`locks.c` calls `mutex_spin_exit`; `vm.c` reads
`uvm_vnodeops`). The alias now takes over that import's symbol slot, so the
existing relocations bind to the definition and the name appears once
([[feature-c-file-scope-asm-symbol-aliases]]).

## Proof

`test/c_asm_label.c` covers a renamed definition, a renamed import, a renamed
variable written from C and read under its label by the gcc main, and the
alias-used-in-file cases for a function and for data. It matches gcc as a
hosted object and as an `-O2 --freestanding` object; the symbols were checked
against gcc's with `nm`.
