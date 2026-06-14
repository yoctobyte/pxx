# Text-assembler codegen helpers (`EmitAsm386` / `EmitAsmX64` …)

- **Type:** feature
- **Status:** in progress (x86-64 core landed 2026-06-14; per-target emitters
  spun off into their own tickets)
- **Owner:** —
- **Blocked-by:** feature-array-of-const
- **Opened:** 2026-06-14 (design discussion: readable asm emission)

## Scope split (this is now the shared-core + x86-64 + inline-asm-unify ticket)

The shared `asmtext.inc` front-end (parser, `%`/`@data`/`@glob`/`.label`
markers, hole binding, rel8/rel32 resolution) and `EmitAsmX64` are **done** here.
Each remaining target is its own incremental ticket, all built on this core,
recommended order (cheapest-first — targets with a typed encoder layer already
done cost least):

- feature-i386-asm-emitter — `EmitAsm386` (shares the x86 ModRM core). **next.**
- feature-rv32-asm-emitter — `EmitAsmRv32` (typed `rv32enc.inc` exists →
  xtensa-shape, cheap).
- feature-aarch64-asm-emitter — `EmitAsmA64` (needs a new thin `a64enc.inc`).
- feature-arm32-asm-emitter — `EmitAsmArm32` (new `arm32enc.inc`; 4-byte align).
- feature-xtensa-asm-emitter — `EmitAsmXtensa` (typed `xtensaenc.inc`). **DONE.**

This ticket retains: further `EmitAsmX64` block conversions + scope item 6
(retarget the user `asm … end` path in `asmenc.inc` onto the shared engine).

## Done so far (2026-06-14)

- `compiler/asmtext.inc`: `EmitAsmX64(const items: array of const)` text
  assembler over the interleaved string/`%`-hole form. Parses one instruction
  per string, binds `%` holes from the following ints, and encodes through the
  typed `x64_*` encoders (so ModRM/REX are computed once). Supported this slice:
  zero-op (ret/leave/syscall/nop/cqo/cdq), push/pop reg, mov (reg,reg | reg,imm |
  reg,[base±disp] | [base±disp],reg), lea reg,[base±disp], and add/sub/and/or/
  xor/cmp (reg,imm | reg,reg). `%` holes for immediates and displacements.
  Operand/register parsing reuses `AsmRegNum` from `asmenc.inc`.
- **Labels + relative jumps**: `name:` defines a label; `jmp`/`jcc name`
  resolve back (rel8 when in range, else rel32) and forward (rel32, patched at
  call end) — the mechanism that will delete the manual CodeLen/Patch32 jump
  sites. Plus `inc`/`dec`, explicit memory sizes (`cmp byte [rax], 0`), and ALU
  r/m,imm.
- `EmitWriteCStr` is now expressed **entirely** in `EmitAsmX64`, including the
  strlen scan loop (back+forward label jumps, `cmp byte [mem]`, `inc`),
  exercised by `test/test_array_of_const.pas` and the new `test/test_asm_emit.pas`
  (varied PChar lengths, FPC-parity).
- Bootstrap stays byte-identical; full `make test` green.

### Self-host landmine hit (fixed)

PXX evaluates `and`/`or` **fully** (no short-circuit), and indexing an EMPTY
AnsiString derefs a nil data pointer. So `(Length(s) > 0) and (s[i] = ..)` still
touches `s[i]` and crashes on an empty string (FPC short-circuits, hence the
divergence: FPC-built compiler fine, PXX-built segfaults). All conditional char
reads in `asmtext.inc` go through `AsmTextCharAt` (range-checked, returns #0).
Also: a `var AnsiString` parameter reassigned in the callee is a frozen-inline
landmine — `AsmTextSizeKeyword` returns the size instead.

Remaining: `@data`/`@glob` reloc holes; single-line overload; `EmitAsmX64` for
more codegen blocks; then `EmitAsm386` and the inline-asm unification.

## Motivation

Codegen currently emits raw bytes — `EmitB($19); EmitB($D3); { sbb ebx,edx }` —
with the mnemonic in a comment. ~970 `EmitB` lines in `ir_codegen386.inc` alone.
It is unreadable and error-prone: this exact pattern produced the session's
`19 DB` vs `19 D3` ModRM bug (`sbb ebx,ebx` instead of `sbb ebx,edx`), which the
assembler-computes-ModRM approach **cannot** make.

Goal: write emit blocks as assembly text, parsed and encoded by a per-target
text-assembler, with runtime values bound inline. Readable, fewer bugs (encode
ModRM/SIB/REX once, correctly), and it **doubles as the backend for built-in
`asm … end` inline assembly** (today a separate, rudimentary x86-64-only parser
in `asmenc.inc`) — one engine, two consumers, every mnemonic added helps both.

## Target shape (depends on `array of const`)

One interleaved `array of const`: each string is one instruction (one
instruction per line — house rule), and the integers right after a string are
that line's hole values, in order.

```pascal
EmitAsm386([
  'push ebp',
  'mov ebp, esp',
  'sub esp, %',            frameSize,
  'mov eax, [ebp+%]',      Syms[si].Offset,
  'mov edi, @data',        INTBUF_OFFSET + INTBUF_SIZE,
'.loop:',
  'mov eax, esi',
  'div ecx',
  'dec edi',
  'jnz .loop',
  'int 0x80'
]);
```

Provide a **single-line overload** so trivial cases skip the brackets:
`EmitAsm386('ret');` / `EmitAsm386('mov eax, %', v);`.

### Binding / marker rules

- `%` — value hole. The next `vtInteger` element is the operand value;
  **width is inferred from the instruction** (`add dl, %` → imm8; `mov ecx, %`
  → imm32; `[ebp+%]` → disp32). No type tag on the hole. Add an explicit `%d8`
  escape only for the rare disp8 form.
- `@data` / `@glob` — relocation hole. Emits the 4-byte placeholder and
  registers the fixup via the existing `EmitDataRef` / `EmitGlobRef` (data vs
  bss can't be inferred, so the kind is explicit). Consumes the next int (the
  offset).
- `.name:` defines a label; `jXX .name` / `jmp .name` reference it. Assembler
  picks rel8/rel32, back or forward — **this deletes the 57 manual
  `CodeLen`/`Patch32` jump sites** in `ir_codegen386.inc`.
- Plain line, no marker → no args consumed.
- The assembler **counts markers per line and validates** the count and types
  of the following elements (mismatch = hard error → catches the ordering
  mistakes the flat-array form invites).

### Why this and not alternatives (settled in design)

- Bare `f('asm', 1, 2)` varargs = compiler magic (writeln); using it would
  make the source FPC-incompatible → breaks `make bootstrap`. Rejected.
- Multiline backtick strings = FPC 3.3.1 only → breaks bootstrap. Not needed;
  the line array reads fine. (Easy to add later as pure sugar once we cut the
  FPC cord; not on the path.)
- `%name`-with-parallel-value-array / records = the "variable mess" the
  interleaved `array of const` avoids. Rejected.

## Scope

1. **x86 text-assembler first** — covers i386 **and** x86-64 from a shared
   ModRM/SIB/(REX) encoder core (the two hottest backends; also the encoding
   layer where the ModRM bug lived). Mnemonic table grown on demand — start
   with exactly the instructions the converted blocks use.
2. Operand parsing: registers (8/16/32/64), `[base+disp]`, immediates, the
   `%` / `@data` / `@glob` / label markers above.
3. Emit through the **existing** byte sink + fixup tables (`EmitB`,
   `EmitDataRef`, `EmitGlobRef`, `Code[]`/`Patch32`) — no new relocation or ELF
   machinery; the assembler is a front-end over what's already there.
4. `EmitAsm386` + `EmitAsmX64` entry points (+ single-line overloads). Later
   `EmitAsmA64` / `EmitAsmArm32` / `EmitAsmRv32` / `EmitAsmXtensa` as those ISAs
   get an assembler (separate, incremental).
5. **Incremental adoption — mix freely.** Convert fixed / label-heavy / lightly
   bound blocks; leave heavily-dynamic blocks (`[ebp+Syms[..].Offset]` with
   many holes) on `EmitB`/typed encoders. No big-bang rewrite.
6. **Unify inline asm**: once the x86 assembler is solid, retarget the user
   `asm … end` path (`asmenc.inc`) onto it so inline asm and codegen share one
   engine (own follow-up slice; the encoder is the shared asset).

## Acceptance

- `EmitAsm386` exists with the marker/label/binding rules above and a
  single-line overload.
- `EmitwriteUInt64_386` (fixed + a backward-jump loop + two `@data`) and at
  least one **bound** site (e.g. the `IR_LOAD_SYM` `[ebp+disp]` path) are
  converted to `EmitAsm386`.
- `make test` + `test-i386` green; the i386 self-fixedpoint stays
  **byte-identical** (native and self use the same assembler, so output may
  shift vs the old hand-bytes but must agree between native↔self — re-verify
  the `cmp`).
- A focused `test/test_asm_emit.pas` exercising imm/disp/label/reloc encodings
  against known-good bytes.

## Notes / landmines

- **Byte-identity discipline:** replacing a hand block changes the emitted
  compiler's bytes; that is fine as long as the fixedpoint `cmp` is clean
  (both sides run the new assembler). Re-run the i386 fixedpoint after each
  conversion batch.
- Keep one instruction per line (house rule) — makes the eventual
  `EmitB`→`EmitAsm` conversions mechanical and diffs legible.
- The assembler runs at compiler runtime; for a hot/pervasive path, parse once
  into a cached byte template with binding holes. Not needed until profiling
  says so.
- Existing per-target encoders (`x64enc.inc`, `rv32enc.inc`, `xtensaenc.inc`,
  `asmenc.inc`) and the done `feature-typed-instruction-encoders` are the seed
  / lower layer the text-assembler sits on top of.

## Log

- 2026-06-14 — opened from the readable-asm-emission design thread. Settled:
  interleaved `array of const` binding, `%`/`@data`/`@glob`/`.label` markers,
  width-inferred holes, single-line overload, x86-first shared ModRM core,
  incremental mix-with-`EmitB`, inline-asm unification as the double-win.
  Gated on feature-array-of-const (the binding vehicle).
