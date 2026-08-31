---
slug: bug-a-q-plus-overflow-checking-has-no-runtime-helper-on-arm32-and-riscv32
track: A
prio: 45
type: bug
blocked-by: []
status: done
found: 2026-08-29
owner: frankA
summary: "FIXED 2026-09-01. NOT a missing helper and not about builtinheap -- the error message is a red herring. `{$Q+}` is a LEXER GLOBAL with one reset per compilation, so it leaked out of the user source into the compiler's own ambient runtime units; softfloat is pulled BEFORE builtinheap and only on arm32/riscv32, so the checks it then emitted called a PXXOverflow that did not exist yet. Fixed by making ParseUsesUnitAmbient compile a compiler-injected unit under the COMPILER defaults. Both targets now trap RE 215 like the other three. Test test_qplus_survives_ambient_units.pas, discriminating (CFAILs on pre-fix c4a89282faa6). Xtensa is a SEPARATE defect, filed. ORIGINAL: `{$Q+}` (overflow checking) fails to COMPILE for arm32 and riscv32 -- `{$Q+}: PXXOverflow runtime helper not found (builtinheap not loaded)`, raised from builtin/softfloat.pas. x86-64 and aarch64 build the same source. Split out of the aarch64 aggregate-result ticket, where it was recorded as an unrelated second finding so it would not be re-discovered as new."
---

# `{$Q+}` overflow checking has no runtime helper on arm32 and riscv32

- **Type:** bug — **Track A** (32-bit backends / runtime helper wiring).
- **Found:** 2026-08-29, alongside
  [[bug-a-aarch64-cannot-build-programs-with-an-aggregate-result-past-8-params]],
  which recorded it verbatim as *"Also seen, same session, unrelated cause"* and
  said to split it out if someone took that ticket. Someone did (frankA,
  2026-08-30), so here it is.

## Repro

```
$ pascal26 --target=arm32   test/test_a64_leafsym_binops.pas /tmp/x
pascal26:86: error: {$Q+}: PXXOverflow runtime helper not found (builtinheap not loaded)
$ pascal26 --target=riscv32 test/test_a64_leafsym_binops.pas /tmp/x
pascal26:86: error: {$Q+}: PXXOverflow runtime helper not found (builtinheap not loaded)
```

Still reproduces at `bfd6e7f0e` with a self-hosted `8444cdce006a`. x86-64 and
aarch64 compile the same file. The error is raised while compiling
`builtin/softfloat.pas`, not the test program, so it is not specific to this
test — it fires for anything that reaches `{$Q+}` code on those two targets.

## Why it is filed separately rather than left where it was found

It shares nothing with the aggregate-result bug but the session that saw it: a
different diagnostic, different targets, different mechanism (a missing runtime
helper rather than an ABI lowering gap). Keeping the two in one ticket meant the
aggregate-result fix would close a ticket that still contained a live, unfixed
second defect — the shape that turns a `done/` entry into a thing nobody rereads.

## What is NOT yet known

**The root cause is unverified.** The message says `builtinheap not loaded`,
which reads as a unit-loading/ordering question rather than a missing
implementation, but nobody has checked whether `PXXOverflow` exists at all for
these targets, whether it exists and is not linked, or whether `{$Q+}` should be
lowering to an inline check on 32-bit instead of a helper call. That is the
first thing to establish, and it decides whether this is a five-line wiring fix
or a codegen gap.

## Cost

`{$Q+}` is how a program asks for arithmetic overflow to be *detected* rather
than silently wrapped, which makes an unbuildable `{$Q+}` a safety feature that
is unavailable on two of six targets — and unavailable loudly, at compile time,
so nothing silently mis-runs. That is the good version of this failure: it
refuses rather than pretending. It still means 32-bit code cannot be built with
the checking its author asked for.

## Gate

`make compiler/pascal26` + `test/test_a64_leafsym_binops.pas` compiles and runs
for arm32 and riscv32 with output matching the x86-64 oracle, plus a `{$Q+}`
program that actually overflows being caught on both targets — the point of the
directive is the trap firing, and a build that merely compiles proves only half.


---

## Fixed 2026-09-01 — the message names the wrong thing

### It is not a missing helper

`uses sysutils` loads builtinheap and **the error does not change**. That single
observation kills the ticket's framing: `PXXOverflow` is present, declared
unconditionally in `builtinheap.pas`, on every target. The problem is **order**,
not absence, and the diagnostic's "(builtinheap not loaded)" sends the reader
somewhere there is nothing to find.

### What it actually is

The error is raised while compiling **the compiler's own source**:

```
pascal26:86: error: {$Q+}: PXXOverflow runtime helper not found (builtinheap not loaded)
  in: ./compiler/builtin/softfloat.pas
  near: Result := Result or 1 ; >>> end ; function
```

`QChecksVal` is a lexer GLOBAL, reset exactly once per compilation in
`PasInitDefines`. A program that leaves `{$Q+}` on at `end.` — the ordinary way
to write it — leaves it on for everything the compiler lexes NEXT, which is its
own ambient runtime units. `pasparser_prog.inc` pulls `softfloat` before
`builtinheap`, so softfloat compiled with overflow checks it never asked for,
and those checks called a helper that had not been declared yet.

**Only arm32 and riscv32 pull softfloat**, which is the whole of why the ticket
reads as a 32-bit-backend problem. It is not one; it is a switch-scoping bug
that those two targets are the only ones positioned to trip.

### The observation that identified it

Moving `{$Q-}` above `end.` made both targets compile **and trap correctly**:

```
{$Q+} c := a + b; {$Q-}     arm32 -> Runtime error 215      riscv32 -> Runtime error 215
```

A missing helper cannot be fixed by turning the switch off later in the file.
That is what said "leak", not "absence".

### The fix

`ParseUsesUnitAmbient` now saves the lexical switch state, resets it to the
compiler defaults, parses the injected unit, and restores. Reset as a block
rather than switch by switch, because the rule is *a unit the program never
asked for is not governed by the program's switches* — stating it once is what
stops the next switch reopening it. **`{$R+}` leaks identically today** and
merely happens not to fail; that is the version of this bug nobody would have
found, and it is now closed too.

Scoped to AMBIENT units — ones the compiler injects. Whether a user's own
`uses` should also stop propagating `{$Q+}` (FPC treats `$Q` as a local switch,
so arguably yes) is left alone deliberately: it is a visible language-semantics
change with no bug behind it today.

### Verified, with a control

`test/test_qplus_survives_ambient_units.pas`, wired native + aarch64 + riscv32 +
arm32 + i386.

| binary | arm32 | riscv32 | i386 | aarch64 |
| --- | --- | --- | --- | --- |
| pre-fix `c4a89282faa6` | **CFAIL** | **CFAIL** | pass | pass |
| post-fix `fc7668c096b2` | pass | pass | pass | pass |

The test **discriminates** — it fails on the old binary, which is the only thing
that makes a green meaningful. The i386 and aarch64 rows pass BOTH ways: they
are controls, not evidence, and are reported as such rather than counted.

The `.pas` deliberately leaves `{$Q+}` on at `end.` and the Makefile says not to
tidy it: adding `{$Q-}` is exactly what made the OLD compiler pass.

### Xtensa is a third, quieter defect and is NOT fixed here

xtensa compiles this and **silently wraps** (`c=-2147483648`, no trap) because it
is the one backend with no overflow-check emitter at all — the only target
absent from the `FindProc('PXXOverflow')` grep. Filed as
[[bug-a-xtensa-has-no-q-plus-overflow-check-emitter-so-it-wraps-silently]], and
it is the same job as
[[bug-a-the-div-by-zero-check-is-still-missing-on-xtensa]].

## Log
- 2026-09-01 — resolved, commit fdb343874.
