---
track: A
prio: 55
type: bug
blocked-by: []
status: done
owner: frank-optimize
found: 2026-08-30
found-by: frank-optimize, finishing chore-a-the-range-checked-fpc-seed-cannot-be-built
summary: "The range-checked FPC seed now BUILDS (make fpc-seed-checked) but traps on its first compile: -Cr range-checks the compiler's deliberate wraparound arithmetic. First site is SymNameFoldHash's FNV-1a multiply in symtab.inc, second is the hex-literal lexer in lexer.inc — it is a chain, not one site. Fix shape is measured and one line per site, but the sites live in files other lanes hold."
---

# The range-checked seed traps on deliberate wraparound arithmetic

`chore-a-the-range-checked-fpc-seed-cannot-be-built` fixed the ten
constant-folding errors that stopped `fpc -Cr` **compiling** `compiler.pas`. The
binary it now produces does not survive its first invocation.

```
$ make fpc-seed-checked
built build/pxx-checked (fpc, -Cr bounds-checked)

$ build/pxx-checked one.npy /tmp/out
ERangeError: Range check error
  SYMNAMEFOLDHASH,  line 3730 of compiler/symtab.inc
  SYMHASHINSERT,    line 3750 of compiler/symtab.inc
  ADDCONST,         line 4908 of compiler/symtab.inc
  main,             line 1872 of compiler/compiler.pas
```

## Why, and why it is not `-Co`'s fault

The obvious first move is to drop `-Co` (overflow checking), since the compiler
wraps on purpose. **Measured: that is not enough.** `-Cr`, `-Crt` and `-Cri` all
trap identically. `-Cr` range-checks the assignment back into `LongWord`, so
deliberate 32-bit wraparound is refused by the bounds flag itself, not only by
the overflow flag.

`SymNameFoldHash` is textbook FNV-1a and the multiply is *supposed* to overflow:

```pascal
h := (h xor LongWord(b)) * LongWord($01000193);
```

## The fix, measured on both compilers

Mask the product back to 32 bits at the assignment:

```pascal
h := ((h xor LongWord(b)) * LongWord($01000193)) and LongWord($FFFFFFFF);
```

| form | `fpc -Crtoi` | pxx |
| --- | --- | --- |
| unmasked | **traps** (runtime error 201) | `3959789884` |
| masked | `3959789884` | `3959789884` |

Same value, both compilers, so the hash is unchanged and no bucket moves. There
are **two** occurrences of that exact line in `symtab.inc` (3730 and 7128) and
both need it — a fix to one leaves the other live.

## It is a chain, not a site

Applying the mask locally (and reverting) gets past the hash. The next trap:

```
EIntOverflow: Arithmetic overflow
  LEXONE,     line 2481 of compiler/lexer.inc
  LEXAPPEND,  line 2732 of compiler/lexer.inc
```

`lexer.inc:2481` is the hex-literal scanner, `n := n*16 + (Ord(c)-48)`,
accumulating a 64-bit bit pattern — so `$FFFFFFFFFFF8DEAD`, which appears in this
compiler's own source, overflows `Int64` on the way in. Same class, same intent,
different type width.

**How many more are behind it is unknown**, and the only way to find out is to
fix each and re-run: `-Cr` reports the first trap and stops. Budget for
iteration rather than for two edits.

## Why bother

Unchanged from the parent ticket, and it is the whole argument: `-Cr` is the only
build in this repo that names an array, a line and the offending index when
something writes past the end. `symtab.inc` alone grows ~30 arrays in lockstep
and `defs.inc` warns that *"a missed one is a silent out-of-bounds"*. Today that
failure shape is debugged by guessing which table overflowed.

## Ownership — the reason this is filed rather than done

`symtab.inc` was held by frankwasm (typeref) and `lexer.inc` is shared A/P, so
the sites were **not edited concurrently**; the parent ticket's own change stayed
in `ir_codegen_aarch64.inc` / `ir_codegen_arm32.inc` / `Makefile`. Whoever takes
this should hold `symtab.inc` and `lexer.inc` together, since the chain crosses
both.

## Gate

`make fpc-seed-checked` builds **and** the resulting `build/pxx-checked` compiles
the corpus without trapping; `make compiler/pascal26` fixedpoint converges (the
masks must not change any emitted byte — verify the hash returns the same values,
which is what keeps bucket assignment identical); `tools/gate.sh quick` GREEN.

Consider adding the checked seed to a gated row once it runs, so it cannot rot
back to unbuildable — which is how it got here: nothing exercised it between the
constants landing and this ticket.

## Resolution (2026-08-30, frank-optimize)

The chain was **three links, four edits**, and it ends: `build/pxx-checked` now
compiles native, i386, arm32, aarch64, riscv32, xtensa and wasm32, at `-O0`,
default and `-O3`, from the Pascal, C and NilPy frontends, including
`compiler.pas` itself.

| link | site | why it wraps on purpose |
| --- | --- | --- |
| 1 | `symtab.inc` FNV-1a multiply, **two** copies (`SymNameFoldHash` and the identical site later in the file) | the overflow IS the hash |
| 2 | the `IRIVal` -> `Int32` immediate argument in `ir_codegen_arm32.inc`, `_riscv32.inc`, `_xtensa.inc` | IR constants are Int64; a Cardinal `$FFFFFFFF` arrives as 4294967295, outside Int32 but exactly the bit pattern a 32-bit target loads |
| 3 | `EmitLoadImmRISCV32`'s lui carry, `hi := hi + $1000` | `addi` sign-extends, so the borrow lands on `$80000000`, which lui wants and Int32 cannot hold |

Link 2 got a named helper rather than three casts — `Low32(v: Int64): Int32` in
`util.inc` — because the four 32-bit backends hold ~130 `IRIVal` references
between them and the trapping ones are discoverable only one abort at a time, so
the next one wants a one-word fix with the rationale already attached. Link 3
reuses it, which is why it is `Low32` and not `IRImm32`.

### Correction to this ticket's own "it is a chain" section

The `lexer.inc:2481` hex-literal trap quoted above is **not in this chain**, and
the ticket was measured wrong. It is an `EIntOverflow`, which needs `-Co`, and
the table two sections up gives away how it got in: those figures came from
`fpc -Crtoi`, while the seed `make fpc-seed-checked` actually builds is `-Crit`
— `-Co` is deliberately excluded there, with a comment saying so. Measuring the
chain under different flags than the seed uses reported a link the seed cannot
reach. `lexer.inc:2481` is untouched and the seed does not care.

### The masks changed nothing, and that is now an assertion

Every emitted byte is identical across the change. Arm A = the binary built from
unedited sources (`8d94efc35610`), arm B = the same sources plus these edits
(`d3fa1fa03ffd`), same inputs both arms: all cross-target outputs `cmp`-equal,
the only diff in the whole set being the `# Executable:` path line in a `.map`,
i.e. an artefact of where the experiment wrote its files.

That property is no longer a memory. `make test-fpc-seed-checked` (wired into
`test-fpc`, the FPC-dependent postcheck — not the daily gate, it costs an FPC
build) runs the checked seed on `test/test_range_checked_seed.pas` and demands
**byte-identical output to the self-hosted compiler** on native, arm32, riscv32
and xtensa. That makes the seed a differential oracle instead of a smoke test:
it fails both if the seed traps and if the two compilers ever disagree.

### The guard was shown to fire before it was trusted

Per `bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire`, a
guard nobody has seen fail is not a guard. Each arm was reverted and rebuilt:

- revert `Low32` at the arm32 / riscv32 / xtensa const-load -> that arm aborts,
  in `IREMITNODE<TARGET>`, and only that arm;
- revert the riscv lui carry -> the riscv32 arm aborts alone, inside
  `EMITLOADIMMRISCV32`;
- the `symtab.inc` FNV site aborts every arm, native included — that was this
  ticket's original repro;
- and `expect_same.sh rcs_values` was fed a wrong expectation and reported
  MISMATCH, exit 1.

### Gate

`make compiler/pascal26` -> `converged after 1 round(s), d3fa1fa03ffd`;
`tools/gate.sh quick` -> GREEN (7/7, self-host fixedpoint 41s).

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
