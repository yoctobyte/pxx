---
slug: feature-c-stack-protector-strong-global-guard
track: C
prio: 70
type: feature
status: done
owner: rd
created: 2026-11-20
found-by: rainyday
tags: [cfront, x86-64, hardening, rainyday, kernel]
blocked-by: []
summary: "gcc's -fstack-protector-strong -mstack-protector-guard=global for x86-64 C, with -fno-stack-protector per file: Rainyday's gcc kernel build has it (their ticket 0030) and the pxx build did not, so it was weaker there."
---

# -fstack-protector-strong with the global guard (x86-64 C)

## The request (Rainyday, 2026-11-20)

The gcc kernel build uses `-fstack-protector-strong
-mstack-protector-guard=global`. A function with local arrays (the strong
rules) keeps a copy of the global `uint64 __stack_chk_guard` below the return
address and calls `__stack_chk_fail()` if the copy changed by the time it
returns. `arch/x86_64/canary.c` sets the guard; it is built with
`-fno-stack-protector` and called from boot.S before kmain. Their check is
`tools/smashtest.sh KERNEL.elf`: it gives ENODEV until `__SSP_STRONG__` is
defined, and then must panic with "stack smashed". Scope as they asked: strong
mode, the global guard, `-fno-stack-protector` per file, x86-64 only.

## What pxx does now

- **Flags.** `-fstack-protector-strong` and `-fno-stack-protector`, the last
  one given wins (as in gcc). `-mstack-protector-guard=global`.
- **Refusals.** These exit 1 with a message instead of being ignored, so a
  hardening flag is never accepted and then quietly not delivered:
  `-fstack-protector`, `-fstack-protector-all`, `-fstack-protector-explicit`,
  any other `-mstack-protector-guard=`, strong mode without the global guard
  (gcc's default is the TLS guard), and any target other than x86-64.
- **`__SSP_STRONG__` = 3**, gcc's value (`__SSP__` is 1, `__SSP_ALL__` 2,
  `__SSP_EXPLICIT__` 4).
- **Which functions.** gcc's strong rule, decided after the body is parsed
  (`CSspNeedsProtection`): a local array, a local struct or union holding one,
  a local or parameter whose address is taken, or alloca/VLA. On
  test/c_stack_protector_strong_rule.c it picks exactly gcc's five functions
  out of seven.
- **The canary slot** is the first local, so it sits at rbp-8, directly under
  the saved rbp. It is reserved in every C function under the flag (8 bytes),
  but only a protected function writes or checks it. Before the body's first
  instruction: `mov r11,[__stack_chk_guard]; mov [rbp-8],r11`.
- **The check** runs in `EmitProcEpilog`, which every `return` and the
  fall-through reach, as the last thing before `leave; ret`, using r11 only:
  `mov r11,[rbp-8]; cmp r11,[__stack_chk_guard]; je ok; call
  __stack_chk_fail`.
- **The two names** are prepended as ordinary declarations (`CAddSspDecls`,
  on line 1 like the builtin prototypes), so in a freestanding object
  `__stack_chk_guard` is an undefined data symbol with a PC32 relocation and
  `__stack_chk_fail` a relocated external call. A file that redeclares the
  guard as `uint64_t`, or defines `__stack_chk_fail` itself, compiles.

## Measured

- **Hosted** (test/c_stack_protector_strong.c, guard and failure handler
  defined in the file): pxx at -O0 and -O3 gives the same output as gcc
  `-fstack-protector-strong -mstack-protector-guard=global`: in bounds runs,
  the overflow prints "stack smashed" and exits 42. Without the flag the same
  overflow segfaults.
- **Freestanding object** linked into a gcc host that defines the guard and
  `__stack_chk_fail`: the overflow is caught (exit 42).
- **The strong rule**, compared function by function against gcc's object:
  identical.

The rows are in test-core, next to the -fcommon rows.

Not done (not asked for): the TLS guard, the other modes, and
`__attribute__((no_stack_protector))`. Each is refused rather than ignored,
except the attribute: it is not a flag, and Rainyday turns canary.c off as a
whole file.
