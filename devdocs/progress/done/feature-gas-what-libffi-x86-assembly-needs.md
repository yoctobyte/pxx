---
slug: feature-gas-what-libffi-x86-assembly-needs
track: gas
prio: 70
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (Panorama all-pxx program: libffi 3.5.2 through compdb.py replay, --shared-runtime --threadsafe)
tags: [gasfront, asmatt, asmenc, relaxation, eh_frame]
summary: "libffi's x86/unix64.S and win64.S assemble with pxx now; libffi replays 10/10 (8 C + 2 .S). Added to the GNU as front: jmp/jcc relaxation (rel8 first, grown by passes); `.org label + N` for a label of the current section; call/jmp through memory; section type @unwind; forward equates (`.set x, a - b` before a or b exists); `X - .` data as R_X86_64_PC32/PC64. Added to the AT&T reader/encoder: movd, fldt, fstpt, movss/movsd with operands, and the operandless movsd/cmpsd string ops. Test: tools/check_gas_frontend.sh step 7, test/gas_frontend_libffi_shapes.S, byte-identical to gas."
---

# What libffi's x86 assembly needs

Found while replaying libffi for the all-pxx Panorama link. After the C side
(feature-c-complex-types-as-layout) only the two `.S` files failed. Each fix
was checked byte for byte against GNU as on the form it adds, then together
in test/gas_frontend_libffi_shapes.S (step 7 of tools/check_gas_frontend.sh,
`.text`, `.eh_frame` and relocations).

In the order libffi hit them:

1. **`.org BASE + X * 8`** (unix64.S's `E(BASE, X)` jump-table check). `.org`
   took only a constant. Now a label already defined in the current section
   plus a constant works too. This is what gas allows without frags.
2. **movd** (`movd %xmm0, (%rdi)`). It was missing from asmatt's whitelist
   and from asmenc. It is 66 0F 6E/7E without REX.W.
3. **fldt / fstpt** (DB /5, DB /7) and **movss / movsd with operands** in
   the AT&T whitelist. asmenc already encoded the SSE moves. An operandless
   `movsd`/`cmpsd` is the dword string op, as gas reads it ("assuming movsl").
4. **Branch relaxation.** gasfront wrote every jmp/jcc as rel32, so a
   16-byte table entry `endbr64; movq; jmp` was 19 bytes and `.org` refused
   to move backwards. Now jmp/jcc start as rel8 (EB, 7x cb). A resolve pass
   that finds a short one out of range, or not resolvable in its own section
   (external, weak, another section), marks it long, and the text is
   assembled again. Branches only grow, so it ends. call stays rel32,
   .code16 is unchanged. Sizes now match gas, and so do relocations.
5. **call/jmp through memory** (`call *16(%rbp)`, win64.S). FF /2 and FF /4
   are push's FF /6 except for the ModRM reg field. The shared encoder writes
   the push and the field is patched. All addressing forms work, rip
   included.
6. **`@unwind`** = SHT_X86_64_UNWIND (0x70000001), gas's type for x86-64
   `.eh_frame`.
7. **Forward equates.** `.set .Lset0, .LECIE - .LSCIE` comes before .LECIE.
   It is kept as an expression (GasSymSec -3) and folded where a fixup uses
   it. It is never a symbol in the object. Redefining one is refused, since a
   use before and after would need two values.
8. **`.long X - .`** with X in another section: the subtrahend is in the
   section being written, so it is R_X86_64_PC32 (PC64 for .quad) with
   A = c + P − m.

Measured on libffi's own objects against gcc's build: the same relocations
(8). The instructions are the same apart from CET. gcc predefines `__CET__`
(Ubuntu's -fcf-protection), so libffi adds endbr64/notrack and 16-byte table
entries. pxx does not, and libffi uses 8-byte entries.

Not done, noticed: pxx writes `.L` labels into the symbol table (gas drops
them), and `cmp $imm8, %cl` gets a redundant 0x40 REX. Both are harmless.
Alignment padding in code is 0x90s, not gas's multi-byte NOPs.
