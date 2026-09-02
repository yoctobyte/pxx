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
