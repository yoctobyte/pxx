---
track: C
tags: [c, int128, attributes, libtommath]
prio: 30
type: feature
blocked-by: []
summary: "pxx has no 128-bit integer: no `__int128`, no `__SIZEOF_INT128__`, and `__attribute__((mode(TI)))` is refused. It also skips the narrower `mode(QI/HI/SI/DI)` without applying them, so `typedef int i8 __attribute__((mode(QI)))` is a 4-byte int where gcc makes it 1 byte."
status: done
owner: claude-dupwt
---

# 128-bit integers, and `__attribute__((mode(...)))` that is honoured

Split out of [[bug-c-attribute-mode-ti-was-ignored-and-made-a-64-bit-type]].

## What exists

- **mode(TI) and wider:** refused by name since 2026-11-13, because ignoring
  them made a silent 64-bit type.
- **mode(QI), mode(HI), mode(SI), mode(DI), mode(word):** still skipped. The
  typedef keeps its base type. That is right when the base already has the
  mode's width, and wrong otherwise (`int ... mode(QI)` should be 1 byte).
  No corpus program has hit this yet; check before relying on it.

## Who wants 128-bit

- libtommath under MP_64BIT (its default for __GNUC__ on 64-bit). dropbear
  works around it with `-DMP_32BIT` (see tools/dropbear_pxx.py). 64-bit
  digits are roughly 2-4x faster for RSA.
- Common elsewhere: curve25519-donna-c64, BearSSL's 64-bit code, and Rust-
  or Go-style hash/PRNG code ported to C (`(unsigned __int128)a * b` for the
  high half of a product).

## Shape of the work

- A `tyInt128`/`tyUInt128` pair, or a two-register lowering limited to
  + - * (low half and full), shifts, compares and casts. Those are what the
  callers above use. Division is a runtime helper, written in pxx's own RTL
  (no libgcc, per the standing rule).
- `__int128`, `unsigned __int128`, `__SIZEOF_INT128__ 16`, and `mode(TI)` as
  an alias. SysV passes `__int128` in two eightbytes (a register pair).
- x86-64 first. Every other target refuses by name until it gets the
  lowering.

## Done 2026-11-18 (x86-64)

`__int128`, `unsigned __int128`, `__int128_t`, `__uint128_t`, `mode(TI)` and
`__SIZEOF_INT128__` (16) work on x86-64. A value lives in rdx:rax, low half in
rax: the i386 Int64 edx:eax model, and also the SysV return convention.

- Types: `tyInt128`/`tyUInt128` (32/33), 16 bytes, 16-aligned. They are
  deliberately NOT `TypeIsOrdinal`/`TypeSigned`; code asks `TypeIsInt128`, so
  no 64-bit arm picks them up by accident.
- Codegen: `compiler/ir_codegen_i128.inc` claims every IR node that produces
  or consumes a 128-bit value (`I128Claims`): constants, sym/mem load and store
  (globals, locals, by-ref params), + - * & | ^ ~ neg, shifts (shld/shrd plus
  the `test cl,64` fixup), all compares, and / %, inline: a fast path when the
  divisor fits in 64 bits (two `div`s) and Hacker's Delight's estimate plus
  correction otherwise; signed division works on the magnitudes. No libgcc
  (`__divti3`) and no RTL helper.
  Any other IR node with a 128-bit operand is an error naming the op, so a
  missed shape cannot silently drop the high half.
- Calls: an `__int128` argument takes two GP registers (SysV), or the stack
  when fewer than two are left; returns come back in rdx:rax.
- Casts: the IR has no cast node and AN_PTR_CAST retags in place, so widening
  to 128 becomes `x + 0` typed 128, which sign- or zero-extends.
- Initialisers: scalar globals, arrays (sized, unsized, 2-D) and struct members.
- Assembler: `shld`/`shrd` by cl and `bsr`/`bsf` reg,reg.
- `x OP= y` with a side-effecting lvalue (`*_W++ += ...`): the address-once
  gate (`IRAssignIsSharedCompound`) admits int128. Before that, libtommath's
  Montgomery reduction stepped `_W` by two and every modexp was wrong.

Tests: `test/c_int128_{basic,calls,init,divide,ptrwalk}.c` match gcc at -O0
and -O2 (`divide` checks 20,000 random signed and unsigned cases);
`test/c_int128_float_refused.c` asserts both refusals below.

Proof: `tools/dropbear_pxx.py` dropped `-DMP_32BIT`, so libtommath uses its
default 64-bit digits with a mode(TI) mp_word. RSA/ECDSA key generation,
ecdh-nistp256/384/521, DH group14 and host keys rsa/ecdsa all pass (38 rows,
1 red: "the server's scp is the pxx scp", which looks up `scp` on the
login shell's PATH. It was red before this change as well, and is unrelated to
the code generator). `PXX_DROPBEAR_MP32=1` restores the old build.

## Not done (refused by name)

- Other targets (aarch64, i386, arm32, riscv32, xtensa): "supported on x86-64
  only so far".
- Conversion to and from floating types ("conversion to a floating type is not
  supported yet"); that needs a correctly rounded __floattidf in the RTL.
- The narrow `mode(QI/HI/SI/DI)` re-sizing is unchanged (still skipped).
- An `__int128` passed in memory is not 16-byte aligned on the stack (SysV
  says it should be). That only matters once a call has run out of registers.

All four are in [[feature-c-int128-other-targets-float-and-narrow-modes]].
