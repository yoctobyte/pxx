---
slug: bug-c-weak-data-references-bind-locally-and-skip-the-got
track: C
prio: 45
type: bug
status: backlog
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
