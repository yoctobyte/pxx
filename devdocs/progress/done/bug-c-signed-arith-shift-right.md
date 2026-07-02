# C signed `>>` is a logical (not arithmetic) shift

- **Type:** bug (codegen / C frontend — correctness) — Track A / C
- **Status:** done (v146) — 32-bit native shift path on every target; the
  64-bit software-decomposed shift path on 32-bit targets (arm32/riscv32/
  xtensa) is a separate, narrower follow-on, not covered
- **Opened:** 2026-06-30 (found in the open-ticket triage sweep)

## Symptom

In C, `>>` on a **signed** int is an arithmetic shift (sign-extends). pxx gives the
wrong result:

```c
int s = -2;
... (s >> 1) ...     /* C: -1 (arithmetic). pxx returns a value != -1 */
```

So negative signed values shift in zeros (logical) instead of the sign bit. Bites
hashing / fixed-point / any signed-bit-twiddling C code.

## Likely cause

The shift lowering uses a logical right shift (`shr`) regardless of operand
signedness, OR the C frontend doesn't pick the arithmetic-shift IR op for signed
operands. Pascal `shr` is logical by design (unsigned), so the split is: C signed
`>>` must lower to an **arithmetic** right shift (`sar` on x86-64); C unsigned and
Pascal `shr` stay logical. Check whether the IR has an arith-shift op or only `shr`.

## Fixed (2026-07-02, pin v146)

`CMakeBinop` (`compiler/cparser.inc`) unconditionally remapped C's `>>` (the
dedicated `tkShr` token, C-lexer only) onto `Ord(tkIdent)` — the sentinel
every backend's codegen already used for logical shr, since Pascal's `shr`
lexes as a plain identifier with no dedicated token. C's signed `>>`, C's
unsigned `>>`, and Pascal's `shr` all collapsed onto this one code path, so
codegen had no way to tell them apart — confirming the ticket's own "Check
whether the IR has an arith-shift op or only shr" question: it only had
`shr`.

Fix: keep a **signed** C `>>` on `tkShr` (previously dead past parse time)
instead of forcing it to `tkIdent`; unsigned stays on the existing logical
path. Added a genuine arithmetic-shift-right codegen case to all six
backends, each verified byte-for-byte against a real cross-assembler
(`aarch64-linux-gnu-as`, `arm-linux-gnueabi-as`, `xtensa-lx106-elf-as`) before
landing:

- x86-64: `sar rax, cl` (ModRM `/7` vs `shr`'s `/5`).
- i386: `sar eax, cl`.
- arm32: `asr r0, r0, r1` (`$E1A00150`).
- aarch64: `asrv x0, x0, x1` (`$9AC12800`).
- riscv32: the already-existing `rv32_sra` encoder (previously only used by
  the `.asm` frontend), now also wired into the 32-bit native binop path.
- xtensa: a new `xtensa_sra` encoder (mirrors `xtensa_srl`, op2 field `9` →
  `0xB`).

`ir.inc`'s `IR_BINOP` validator needed a `tkShr` carve-out mirroring the one
`tkXor` already had (its allow-list only accepted operator ids up to
`tkShl`, plus that one explicit exception).

**Scope note:** only the 32-bit *native* register shift path is fixed. The
separate 64-bit *software-decomposed* shift path used on 32-bit targets for
Int64/UInt64 (arm32/riscv32/xtensa each have one) is not touched — C's
`long`/`long long` signed `>>` on those targets needs a narrower follow-on
(sign-extension only in specific places of a 64-bit shift split across two
32-bit halves); not exercised by this ticket's own `int`-only repro.

**Verification:** exact match against a real GCC oracle on host (signed/
unsigned/variable-shift-count cases). Cross-target exit-code oracle
(`test/csigned_arith_shift_right_b137.c`) identical on host/i386/arm32/
aarch64/riscv32 (xtensa has no C-frontend entry stub yet, so unreachable via
C right now, but assembler-verified). Confirmed the test fails pre-fix
(exit 1) and passes post-fix (exit 42). Full `make test` green (593 `ok:`),
`make test-lua` green, self-host byte-identical.

Committed as `9ab520aa` (pin v146).

## Acceptance

- [x] `(-2) >> 1 == -1`, `(-8) >> 2 == -2` for signed C ints across targets
      (32-bit native shift path); unsigned `>>` and Pascal `shr` unchanged;
      test. **Done, pin v146.**
- [ ] 64-bit (`long`/`long long`) signed `>>` on 32-bit targets' software-
      decomposed shift path — separate, narrower follow-on, not covered.

Relates to [[feature-c-unsigned-semantics-suite-resweep]].
