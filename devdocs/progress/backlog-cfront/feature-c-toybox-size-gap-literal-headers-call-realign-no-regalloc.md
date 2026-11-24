---
slug: feature-c-toybox-size-gap-literal-headers-call-realign-no-regalloc
track: C
prio: 55
type: feature
status: backlog
created: 2026-11-15
found-by: size root-cause measurement of toybox 0.8.15 (default build, 3ae36d29f5, --function-sections)
tags: [cfront, codegen, size]
blocked-by: []
summary: "(1) and (2) done (2026-11-22/23); open: (3) register allocation. pxx's toybox is 1,688,048 bytes, static with its own libc. gcc's is 475,648 (-Os, dynamic glibc), and 2,037,248 stripped if linked static. On toybox's own code pxx emits ~3.6x gcc: 838 shared functions are 838 KB vs 286 KB, a ratio of about 3.3 at every function size; pxx executes 5.0x the instructions. Gap breakdown: codegen density ~743 KB (61%); runtime in the file ~300 KB (25%, only because glibc is a .so for gcc; weak merging works, no duplicates); C string literals ~190 KB (16%), each carrying a 32-byte AnsiString header plus 16-byte alignment (154 KB of headers over 4,805 literals, 35 KB padding; only 5.5 KB is duplicate text). -O2 changes nothing for C (byte-identical sections). Fixes by cost: (1) emit C literals as plain bytes in .rodata, about -190 KB; (2) drop the per-call stack realignment where the frame depth is already known, 18 B x 8,669 calls, up to -156 KB; (3) register allocation for locals (rbp slot traffic 307 KB + movslq reloads 56 KB), the big one, with cheap peepholes meanwhile (branch on the compare instead of setcc/movzb/cmp, -40..55 KB; add/sub $0, -19 KB). Scripts and data: the session scratchpad tbsize/ (gone after the next wipe)."
---

## Item (1) done 2026-11-22 (claude-pxx): C literals are plain bytes

A C string literal is now its bytes and a NUL in data (InternCStr,
emit.inc). It is deduplicated, unaligned and read-only. Before, it was a
pooled managed-string handle with a 32-byte header and 8-byte alignment.
The C AN_STR_LIT lowering yields IR_CONST_DATA for it, so the `+ 8` past
the length prefix is gone as well. Pascal literals are unchanged.

Two consequences, both fixed in the same change:
- In a `--function-sections` object each literal is its own section,
  `.rodata.pxx.cstrN`, flagged A with alignment 1, like gcc's
  `.rodata.str1.1`. Uncut, the literals rode in whichever data section
  preceded them, and the link GC kept that section alive
  (c_link_gc_dead_undefined_ref went red).
- pxx's hosted `--link` now places `.rodata.*` in a read-only `.rodata`
  after `.text`, as freestanding links already did. It used to merge them
  into `.data`. That merge never showed before, because no `.rodata` input
  had survived the GC in the ld cross-check
  (tools/elf_reader_vs_readelf.sh, which now pins `.rodata` at pxx's
  address too). A C `const` object in a hosted executable is therefore
  read-only now, as with gcc.

Measured with the same sources, before and after:

| program | before | after |
|---|---|---|
| 900-literal test program, data | 61168 | 19802 |
| ...code | 95501 | 91117 |
| Rainyday esp32s3 kernel (text+data) | 1129560 | 1111196 (-18.4 KB) |
| Rainyday pc kernel (text+data) | 1804689 | 1758999 (-45.7 KB) |

Both Rainyday kernels boot in QEMU as before. Toybox was not re-measured.

Test c_string_literal_plain_bytes (gcc-checked on x86-64 and i386, the same
on aarch64, arm32, riscv32 and wasm32) covers indexing, deref, sizeof,
concatenation, embedded NULs, dedup, global tables and returned literals.
Row c_litraw26_sec checks the object layout.

## `add/sub $0` done 2026-11-23 (claude-pxx)

The x86-64 IR_FIELD arm emits nothing for a field at offset 0, and the
imm-fold binop arm emits nothing for `+ 0`, `- 0`, `| 0` and `^ 0`. The
Rainyday pc kernel had 3058 `add $0x0,%rax` and 74 `sub $0x0,%rax`; it
now has none, and its text is 12.8 KB smaller (1716903 -> 1704131). It
boots as before. Rows c_fz026 (the values, against gcc) and c_noaddzero26
(the count). Still open here: (2) the per-call realignment and (3) register
allocation. (2) needs a static rsp depth, and x86-64 codegen does not track
one: pushes come both from the text assembler and from raw EmitB bytes.

## `&&`/`||` on 0/1 operands done 2026-11-23 (claude-pxx)

CMakeTruthy no longer wraps an operand that is already 0/1 (a comparison,
`!`, or an and/or of two such) in `!= 0`. The Rainyday pc kernel had 2242
`setcc; movzx; cmp 0; setne; movzx` doubles. Text, same source:

| kernel | before | after |
|---|---|---|
| pc | 1704131 | 1628910 (-75 KB) |
| esp32s3 | 1108956 | 1044536 (-64 KB, 5.8%) |

Both boot as before. Test c_logical_operand_already_boolean, gcc-checked on
x86-64, i386, aarch64, arm32, riscv32 and wasm32 and at -O2; rows on x86-64
and aarch64.

## Negated short-circuit conditions done 2026-11-23 (claude-pxx)

IRLowerCondJump branches on x and y for `(x && y) == 0` (a C `!(x && y)`,
and every `for` test of an `&&`/`||`, built as `if (cond == 0) break`),
instead of storing the `&&` in a temp. pc text 1628910 -> 1622846
(-6.1 KB), esp32s3 1044536 -> 1041804 (-2.7 KB); both boot. The ~1400
bool store/reload pairs left are value uses (`return a && b;`, `x = a < b`)
and need the register-allocation item. Test c_negated_short_circuit_branch.

## `xor eax, eax` for al = 0 done 2026-11-23 (claude-pxx)

Before a C call x86-64 set al (vector registers used, for variadic
callees) with `mov eax, 0`, 5 bytes, before 10935 calls in the Rainyday pc
kernel. `xor eax, eax` is 2; the flags it clobbers are dead before a call.
pc text 1622846 -> 1589910 (-32.9 KB); boots. Test
c_vararg_vector_count_zero, row c_vacnt26.

Correction: row c_noaddzero26 (72d13651f7) counted in an executable, which
objdump cannot disassemble (no section headers), so it printed 0 whatever
the code. It and c_vacnt26 now count in an `--emit-obj` object; both fail
with the compiler from before their fix (545 and 585) and pass now.

## Store->reload for C locals at -O2 done 2026-11-23 (claude-pxx)

IRMarkRedundantReloads (the -O3 pass: a load is dropped only when nothing at
all is emitted between the store and it) now also runs for C at -O2, the
default. In C it never takes a global: pxx drops `volatile`, so a volatile
global (a flag an interrupt handler writes) would look like any other.
Globals were 244 bytes of the gain anyway. pc text 1589910 -> 1581379
(-8.5 KB); boots. Far less than the ~6800 same-slot pairs suggest: most of
them are inside one statement or across a construct the pass does not
see through, which is the register-allocation item again.

Also found and fixed while measuring -O3 (which is larger than -O2 for the
kernel, 1626396): bug-freestanding-o3-trips-the-no-sse-refusal.

Correction, same day: fc7bbfef34 still skipped the reload of a VOLATILE
LOCAL (`volatile int x = 3; x = 4; return x + x;` read x from rax once),
which gcc never does. The C lexer drops `volatile` before it is a token,
so it now marks the token after the word (CAttrFlags $8000), and
ParseCSubroutine keeps every reload in a definition holding one
(CBodyMentionsVolatile). Cost: 289 bytes of pc text. Test
c_volatile_local_reloaded, row c_volrl26_marks. A typedef'd volatile scalar
local is still not seen; recording volatile on symbols would close that.

## (2) The per-call realignment done 2026-11-23 (claude-pxx)

Every C call was wrapped in `mov r11, rsp; and rsp, -16; push r11` and
`sub rsp, 8` (when the stack arguments were even), with `mov rsp, [rsp+8]`
after it: 18 bytes. The Rainyday pc kernel had 14,941 of these, ~269 KB.

The x86-64 code generator now knows rsp in a C body:
- The body aligns rsp once, right after the prologue: `and rsp, -16` (only
  a C body that makes a call and has no alloca, and not for Windows).
  `leave` restores rsp from rbp, so the epilogue is unaffected.
- Every IR statement row starts at that base, depth 0.
- EmitAsmX64 counts each push, pop and `sub/add rsp, N` it assembles
  (X64DepthScan, asmtext.inc). The x86-64 raw-byte ones call X64DepthAdd.
  Any other write to rsp makes the depth unknown, and that call realigns
  the old way. After the old sequence the count is restored, because the
  sequence puts rsp back exactly.
- A call pads with one `push rax` when the depth plus its stack arguments is
  8 mod 16, and afterwards drops pad and arguments with `add rsp, N` (or
  `pop r11` for 8). The drop is computed from the call alone, so a miscount
  could misalign a call but never lose rsp. The compiler also refuses to
  emit a call whose count is not 0 mod 16 at the call instruction.
- An indirect call reads its callee from `[rsp + args + pad]`. Nothing is
  read back from the stack after any call, so a returns-twice callee
  (setjmp through a pointer, why IRCallRspSlot exists) is fine on this path.

Proof of the count: PXXDBG=x.rspcheck puts `test spl, 15; jz; ud2` before
every call that skipped its realignment. The Rainyday pc kernel built that
way (10,957 checks) boots and passes `test` and `test-sh`, and the C
conformance suite passes 220/220 with it. PXXDBG=x.realign turns the whole
thing off; PXXDBG=x.depth prints each place the count gives up.

| pc kernel text | bytes |
|---|---|
| before (PXXDBG=x.realign) | 1,584,884 |
| after | 1,396,804 (-188 KB, -11.9%) |

Test c_call_alignment_without_per_call_realign: each callee checks a local
declared aligned(16), reached from nested calls in arguments, stack
arguments, an __int128 pad slot, varargs with doubles, indirect calls, ?:
and &&/|| in arguments, a struct by value and a setjmp body. Same output as
gcc at -O0, -O1 and -O3 and under x.rspcheck. Control: a compiler padding
the wrong way (its compile-time refusal disabled) reports 25 misaligned
calls, and under x.rspcheck traps. Row c_callal26_one_realign: main keeps
one `and rsp, -16` (42 before).

Left: the stack-protector failure call in each protected epilogue still
realigns (cold, never returns). Pascal bodies are unchanged. A Pascal body's
statement rows are not known to be balanced (exception frames), so it has
no count.

Found on the way, not changed: `__builtin_frame_address(0)` is the address
of a hidden local, not rbp (by design, cparser.inc), so it cannot probe
alignment.

Still open here: (3) register allocation for locals.
