---
track: A
prio: 55
type: bug
blocked-by: []
status: new
owner: ""
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
