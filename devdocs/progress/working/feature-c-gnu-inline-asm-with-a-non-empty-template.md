---
slug: feature-c-gnu-inline-asm-with-a-non-empty-template
track: C
type: feature
prio: 40
status: working
found: 2026-09-02
found-by: frankD
blocked-by: []
summary: "pxx's C frontend refuses GNU inline asm whose template is non-empty (`error: C: inline asm with a non-empty template is not supported — the instructions would be silently dropped`). The refusal is right; the gap is real. It is the LAST non-crtl blocker for busybox at 258 applets: networking/tls_sp_c32.c takes an x86-64 asm arm because pxx announces __GNUC__, and its failure takes the 400-object link down with it (curve_P256_compute_pubkey_and_premaster undefined). Everything else in that build now compiles."
owner: frankB
---

# GNU inline asm with a non-empty template

```
pascal26:283: error: C: inline asm with a non-empty template is not supported
  in: ./networking/tls_sp_c32.c
```

The refusal itself is the right behaviour and should stay until this lands:
accepting the construct and dropping the instructions is how a program computes
a plausible wrong answer.

## Where it bites, measured 2026-09-02 at 258 applets / 400 translation units

- **networking/tls_sp_c32.c** — the only remaining non-crtl failure in the
  build. Its asm arms are guarded `#if ALLOW_ASM && defined(__GNUC__) &&
  defined(__x86_64__)`, and pxx announces `__GNUC__` (which is also why lua
  takes its computed-goto interpreter here). There IS a portable `#else` arm in
  the file; we do not reach it. **Its failure is also the link failure** —
  `undefined reference to curve_P256_compute_pubkey_and_premaster` is this one
  object missing, not a separate defect.
- **Not** `networking/udhcp/dhcpc.c`, which reported the same error until
  2026-09-02. That one was the HOST's `<asm/swab.h>`
  (`__asm__("bswapl %0" : "=r" (val) : "0" (val))`), reached through
  `<linux/filter.h>`, and is fixed by shadowing that one header with a file
  that defines no `__arch_swab*` so `<linux/swab.h>` takes its own portable
  branch. Worth knowing before this ticket is picked up: **the error names the
  file it was reached FROM, not the file the asm is in**, and that cost one
  wrong diagnosis already.

## Do NOT "fix" this by un-announcing `__GNUC__`

It would make tls_sp_c32.c take its portable arm and would also cost the
computed-goto interpreter in lua, `__attribute__` handling, and every other arm
real C guards that way. The announcement is correct; we do announce a GNU C
dialect. This is a piece of that dialect we have not built.

## Shape of the work

**MOST OF THIS IS ALREADY BUILT, FOR PASCAL, ON SIX TARGETS.** Measured
2026-09-02 (frankuser) — read this before scoping, the original wording below
described building an assembler that exists:

- `compiler/asmenc.inc` is a real inline assembler with a per-target parse body
  for x86-64, i386, aarch64, arm32, xtensa and riscv32.
- Its operands already resolve **by name to a local, param, global or
  register** — locals and params become `[rbp+disp32]` (asmenc.inc:6), globals
  get a deferred `AsmGlobFix` entry patched with the real `EmitGlobRef` at
  codegen.
- Pascal's `asm` lowers to `IR_ASM` carrying a token span; `ir_codegen.inc:6402`
  blits the pre-encoded bytes 1:1, fixing up global operands.

So "encode instruction text, resolve variable operands to stack slots and
globals, on every target" is **done and proven**. That is the bulk of it.

### What is genuinely missing: the ALLOCATOR CONTRACT, not the assembler

Pascal's model is *the programmer names the register and owns the consequences*.
**Clobber lists are parsed and DISCARDED** — four sites say so in as many words
(asmenc.inc:1787, 1885, 1910, 2048) — and that is safe for Pascal precisely
because the register was explicit. GNU asm inverts it: `"r"` means *the compiler
picks and tells you which*, via `%0` substitution, and a clobber is a promise
the compiler must honour. Nothing in the current path talks to the register
allocator at all.

The second constraint is that Pascal asm is **encoded at PARSE time** into
`AsmBytes`. A register chosen at codegen cannot reach it, so either the choice
is fixed at parse time or the encoding must be deferred.

### The slice that avoids both problems

Pin `"r"` to a **fixed scratch register and save/restore around the block**.
Conservative, slower than gcc, correct, and it needs no allocator work — which
turns the first slice into a *translation layer* over the existing engine:
rewrite `%N` into text the per-target parse body already accepts, `"m"` to the
variable's name (asmenc resolves it), `"r"` to the pinned register with a load
before and, for outputs, a store after.

**Fixed-register constraints (`"=a"`, `"=d"`, `"a"`) are the EASY case, not the
hard one** — the register is named by the constraint, so there is nothing to
choose. That matters here because `tls_sp_c32.c` is bignum crypto: `mulq` and
carry chains want exactly those.

### Still to measure before estimating

**Which constraints does `tls_sp_c32.c` actually use?** Nobody has looked.
`"r"`/`"m"`/`"=a"` is a translation layer; `"+r"` with tied operands, or
`asm goto`, is more. There is no busybox tree on plexus, so this needs doing on
a host that has one.

### Not new work

The C parser currently **discards** the operand sections — it counts colons and
skips tokens on paren depth (cparser.inc:7117-7134). Capturing constraint and
expression pairs is genuinely new, but it is small.

`barrier()` (`asm volatile ("":::"memory")`) already works, because an EMPTY
template is accepted.

## MEASURED 2026-09-02 (frankB): the constraint census, and it inverts the plan

busybox @ `1a64f6a20aaf6e` via `tools/install_lib_candidates.sh busybox`;
`networking/tls_sp_c32.c` md5 `fe8e47a4f7d5ca797ddc9241672088d0` (identical to
frankD's tree). Repro confirmed on `compiler/pascal26` at `279763aa9`:
`--emit-obj` on a four-line `"=r"/"r"` probe gives the ticket's error verbatim.

**Exactly four asm blocks are reachable on x86-64.** The other five are the
`__i386__` arms and one `#elif 0` (an untested ARM draft, never preprocessed).

| block | outputs | inputs | clobbers |
| --- | --- | --- | --- |
| 260 `sp_256_add_8` | `"=r"` ×4 | `"0" "1" "2"` | `memory` |
| 356 `sp_256_sub_8` | `"=r"` ×4 | `"0" "1" "2"` | `memory` |
| 431 `sp_256_sub_8_p256_mod` | `"=r"` ×3 | `"0"`, `"1"`(literal) | `memory` |
| 519 `sp_256to512_mul_8` inner | `"=rm"` ×3 | `"0" "1" "2"`, `"a"`, `"m"` | `cc`, `dx` |

Vocabulary: `"=r" "=rm" "m" "a" "0" "1" "2"`, clobbers `memory cc dx`. **No
`"+r"`, no `asm goto`, no named `[sym]` operands** (those are in the dead arm).

### The ticket's "genuinely missing" piece is not missing — there is no allocator

The scoping above says the gap is *the allocator contract*, and names tied
operands as the hard case. Both dissolve here:

- **`grep -n 'RegAlloc\|AllocReg\|register allocator' compiler/*.inc` returns
  nothing.** pxx's x86-64 codegen keeps nothing live in registers across
  statements — which is exactly why `AsmParseBody` can discard clobbers
  (asmenc.inc:2048 says so, and the empty grep is a second source that fails
  differently). So `memory`, `cc` and `dx` are all free, provided the pinned
  scratch pool avoids `rdx`.
- **Tied operands are only hard when you allocate.** Under the ticket's own
  pinning scheme, operand *N* IS a fixed register, so `"0"(a)` means "load `a`
  into that same register first" — satisfied by construction. Tied is the
  cheapest constraint here, not the dearest.

### What is actually missing: a syntax front, which nobody costed

**GNU templates are AT&T. `asmenc`'s x86-64 body is Intel, and it is not text.**
The scoping's "rewrite `%N` into text the per-target parse body already accepts"
holds for i386/aarch64/arm32/xtensa/riscv32, which go through
`AsmParseBodyText*` and emit *text lines*. x86-64 does not: `AsmParseBody` pulls
**tokens from the Pascal lexer** and encodes into `AsmBytes` immediately, and
`AsmParseOperand` wants `[rax+8]`, bare register names, `qword ptr`, no `$`.
`movq 1*8(%0), %3` shares no syntax with that. So the real first slice is an
AT&T scanner over the template string that drives `AsmDispatch` directly:
operand order reversal, `$imm`, `%%reg`, `disp(base)` with `1*8` folded, and
suffix→size where no register fixes it (`sbbq $0, 2*8(%0)`).

Two smaller real gaps:
- **`adc`, `sbb`, `cmc` are absent from `AsmDispatch`** (822-1260). All four
  blocks are carry chains; none of them can encode today.
- **`"m" (bb[j])` is not a name.** `AsmParseOperand` resolves operands by
  `FindSym`; an indexed lvalue has no symbol. Its address has to be materialised
  into a pinned register and substituted as `[rN]`.

### Consequence for the architecture

The template bytes can still be encoded at parse time *because* pinning makes
them register-only — but the loads/stores around the block need frame offsets,
which C does not have at parse time. So `IR_ASM` grows an operand table
(currently `IRA`/`IRB` are just offset+len into `AsmBytes`) and codegen emits
`mov rN, [rbp+off]` / `mov [rbp+off], rN` around the blit, where offsets are
known. That keeps `AsmBytes` as the one encoder and adds no second path.

**Estimate, now that the list exists:** not the translation layer the scoping
hoped for, but not allocator work either. It is an AT&T front end plus three
mnemonics plus an operand table on one IR node. The hard refusal stays for every
constraint not on the table above.
