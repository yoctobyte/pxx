---
track: C
tags: [C, linker, aarch64, dropbear]
prio: 40
type: feature
blocked-by: []
summary: "pascal26 --link now links aarch64 objects (the ones --target=aarch64 --emit-obj writes) into a static aarch64 executable, with no ld. It applies R_AARCH64_ABS64/ABS32/PREL32, MOVW_UABS_G0..G3 and JUMP26/CALL26 relocations, synthesises an aarch64 _start (argc/argv/envp, the .init_array walk, exit(2) with main's value), and writes EM_AARCH64. The C frontend now emits the init/fini thunk for aarch64 --emit-obj objects too, so environ is set before main. A link that mixes machines is refused by name. dropbear builds for aarch64 with it."
status: done
owner: unassigned
---

# pascal26 --link on aarch64

Found building dropbear for aarch64 ([[feature-c-dropbear-builds-with-pxx]],
acceptance 5). All 230 translation units compiled, and then the link failed:
"--link: x86-64 only". plexus has no aarch64 linker (no lld, and binutils has
no aarch64 target), so the in-house linker was the only route.

## What changed

- **elfreader.inc.**
  - `ElfLnkMachine` is set from `--target` and checked against every input's
    e_machine. Mixing machines is refused: "e_machine is 183, and this link
    is for 62 ...".
  - The stub size is per machine: 93 bytes on x86-64, 128 on aarch64.
  - `ElfLnkRelocateA64` handles:
    - ABS64 and ABS32 (S+A), and PREL32 (S+A-P).
    - MOVW_UABS_G0..G3: imm16 goes in bits [20:5], and the checked forms
      verify the range.
    - JUMP26/CALL26: imm26 = (S+A-P)/4, within ±128 MiB.

    An instruction relocation patches the word the object wrote, so the
    opcode and register bits are kept.
  - `ElfLnkPutStubA64` is the x86-64 `_start` contract, word for word in
    aarch64, encoded with llvm-mc:
    - argc/argv/envp go in x19..x21, and the .init_array bounds in x22/x23
      as literal quads.
    - Every init entry and main get (x0, x1, x2) = (argc, argv, envp).
    - It ends with `mov x8,#93; svc #0`.
- **symtab.inc.** `EmitSharedThunkPrologue/Epilogue` have an aarch64 arm. It
  is a 160-byte frame saving fp/lr, x19..x28 and d8..d15, as AAPCS64 asks.
- **cparser.inc.** The init/fini thunk is now emitted for aarch64
  `--emit-obj`, and its envp arrives in x2 (`mov x0, x2`, then
  `__pxx_set_environ`). Before this, an aarch64 object had no .init_array at
  all. getenv would have returned NULL under any linker, including gcc's.
- **compiler.pas.** `--link` accepts aarch64. `--link --freestanding` stays
  x86-64 only.

## Tests

- Row `clnka64` (test-core) builds `test/c_link_aarch64_a.c` and
  `test/c_link_aarch64_b.c` as two aarch64 objects and links them with
  `--link`. It runs the result under qemu and requires gcc's output and
  exit status 3. The pair covers:
  - a cross-object call;
  - a global written from both sides;
  - an ABS64 pointer to the other object's data;
  - function-pointer and string tables;
  - argv;
  - getenv, which proves the .init_array walk set environ.
- Row `clnka64_mixed`: an aarch64 object given to an x86-64 `--link` is
  refused with the e_machine message.
- End to end: `python3 tools/dropbear_pxx.py --target aarch64`.
