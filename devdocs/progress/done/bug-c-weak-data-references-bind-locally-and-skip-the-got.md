---
slug: bug-c-weak-data-references-bind-locally-and-skip-the-got
track: C
prio: 45
type: bug
status: done
created: 2026-11-18
found-by: pxx2 session, rump-pxx g21 follow-up (frank-user found the strong UND)
tags: [cfront, emit-obj, link, weak, rump]
blocked-by: []
owner: claude-dupwt
summary: "Weak DATA symbols now have the right binding in an object (WEAK UND for an undefined weak extern, WEAK for a weak definition), but three gaps remain: (a) a reference to weak undefined data is R_X86_64_PC32, which a PIE link refuses (gcc uses GOTPCREL); (b) a reference inside the same object to a weak data DEFINITION is bound locally, so another object's strong definition does not replace it (gcc and pxx --link both print the weak value); (c) a pxx PROGRAM refuses an undefined weak extern instead of resolving its address to 0."
---

# Weak data: local binding, no GOT, program mode

Repro: test/c_weak_data_a.c (+ c_weak_data_b.c for the override).

Measured 2026-11-18 on x86-64:
- `gcc -o x c_weak_data_a.o` (PIE default): "relocation R_X86_64_PC32 against
  undefined symbol `__stop_maybe' can not be used when making a PIE object".
  `gcc -no-pie` links and prints `1 1 4`, as gcc's own build does.
- `gcc -no-pie a.o b.o` and `pxx --link a.o b.o` print `1 1 4`; gcc's own
  build prints `1 1 40`. main's load of `wv` does not go through the symbol.
- `pxx c_weak_data_a.c` (a program): "undefined reference to extern variable
  `maybe_v', `__stop_maybe'". gcc's program prints `1 1 4`. Skipping the check
  alone would be worse: the variable would get its own nonzero slot.

The Makefile row (after c_weak_l in test-core) asserts the binding and the
non-PIE link; the override is noted there as not asserted yet.

NetBSD rump links kernel-style (non-PIE), where (a) does not bite; (b) matters
where rump overrides a weak default, (c) never (rump code is built as objects).


# Fixed 2026-11-19 (claude-dupwt): all three

**(b) was not binding.** References to `wv` already named the symbol. The
cause was the initialiser: `= 4` was a store in a.o's start-up code, and it
went through the symbol, so after b.o's strong `wv = 40` won the link, a.o's
start-up overwrote it with 4. A weak data definition in an x86-64 object is
now placed in .data and its constant initialiser baked there (the
CStaticDataMode machinery, enabled per symbol: both placement sites in
cparser.inc and the CTryBakeGlobalInit door). The weak copy's bytes are
discarded with the copy. A non-constant initialiser on a weak definition is
still a start-up store, which is not reachable in rump and not covered here.

**(a)** An undefined weak variable (CWeakDataViaGot: x86-64 object,
SymObjDataWeak, ObjDataIsImport) is reached only through its address.
IRAppend sends LOAD_SYM/STORE_SYM/SLOTADDR to IR_LEA, and the x86-64 IR_LEA
emits `mov rax, [rip + x@GOTPCREL]` (EmitWeakDataGotAddr, GlobFixTls = 3,
written as R_X86_64_REX_GOTPCRELX, -4). The relocations now equal gcc's.
pxx's own linker (elfreader.inc) relaxes GOTPCREL/GOTPCRELX/REX_GOTPCRELX
on a `mov reg,[rip+]` as ld does: `lea` for a defined symbol, `mov reg, 0`
(C7 /0 imm32, REX.R to REX.B) for an undefined weak one. Any other
instruction under a GOT relocation is refused, since that linker has no GOT.

**(c)** In an executable an undefined weak variable's address is the
constant 0 (CWeakDataIsNull, the same IRAppend door), and
CheckUndefinedExternData lets weak names through. If one turns out to be
defined after a use was compiled as 0, it is refused with a message (an
extern-weak use followed by a definition, measured, prints the definition's
7, so the guard did not fire there).

## Measured (x86-64)

| link | before | after | gcc |
| --- | --- | --- | --- |
| gcc (PIE) a.o | PC32 refused | 1 1 4 | 1 1 4 |
| gcc (PIE) a.o b.o | refused | 1 1 40 | 1 1 40 |
| gcc -no-pie a.o b.o | 1 1 4 | 1 1 40 | 1 1 40 |
| pxx --link a.o b.o | 1 1 4 | 1 1 40 | |
| pxx --link a.o | 1 1 4 | 1 1 4 | |
| pxx program a.c | refused | 1 1 4 | 1 1 4 |

The test-core row after c_weak_l asserts all of them (c_wkd_*).
