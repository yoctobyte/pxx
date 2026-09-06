---
slug: bug-a-assert-is-undefined-on-the-esp-bare-profile
track: A+S
prio: 45
type: bug
status: backlog
found: 2026-09-06
found-by: frankF
owner: ""
blocked-by: []
summary: "`Assert(i = 1)` in a five-line program answers `error: undefined variable (Assert)` under `--esp-profile=bare` on BOTH chips, so no program containing an assertion can be built for bare metal at all. It works everywhere else, measured: all three IDF-profile spellings (riscv32, xtensa call0, xtensa windowed) compile it, as do hosted riscv32 and x86-64. Cause is not ESP-specific machinery — the parser's soft-alias for `Assert` is gated on `FindProc('__pxxAssert') >= 0` (pasparser_stmt.inc:6448) and bare pulls no `builtin` unit, so the alias never fires and `Assert` falls through the identifier path as a VARIABLE. AnsiString, concatenation and Halt work on bare (measured on the DEVICE); `writeln` does NOT -- it is a documented no-op (docs/targets/esp32.md:70), so the helper must write the failure to the UART0 TX FIFO itself; the fix is the on-demand injection `softfloat` already uses, NOT pulling `builtin` (which genuinely does not compile for ESP — verified, it dies on PXXVarBinOp and PxxSciDigits17)."
---

# `Assert` is undefined on `--esp-profile=bare`

## Measured

`compiler/pascal26 = c9de36a3754e` at `d6de711d1`, `converged after 1 round(s)`.

    program a;
    var i: Integer;
    begin
      i := 1;
      Assert(i = 1);
    end.

| build | result |
| --- | --- |
| `--target=esp32s3 --esp-profile=bare` | **`pascal26:5: error: undefined variable (Assert)`** |
| `--target=esp32c3 --esp-profile=bare` | **same error** |
| `--target=riscv32 --platform=esp` | ok, procs=603 |
| `--target=xtensa --platform=esp` | ok, procs=606 |
| `--target=xtensa --xtensa-abi=windowed --platform=esp` | ok, procs=606 |
| `--target=riscv32` (hosted) | ok, procs=580 |
| x86-64 | ok, procs=554 |

So this is the BARE profile only, not ESP and not xtensa. Remove the `Assert`
line and the same program builds for bare on both chips.

## Cause

`pasparser_stmt.inc:6443` recognises a bare `Assert(` only when every clause
holds, and the last one is `(FindProc('__pxxAssert') >= 0)`. `__pxxAssert` lives
in `compiler/builtin/builtin.pas`, and `pasparser_prog.inc` guards the
`needsBuiltin` injections with `not TargetIsEspClass`. Bare therefore has no
`__pxxAssert`, the alias does not fire, and the name reaches the ordinary
identifier path — which is why the diagnostic calls a procedure a **variable**.

**The soft-alias discipline is right and is not the bug.** It exists so a user's
own `Assert` still wins (same shape as `Move`/`FillChar`), and a guard that
falls through silently is the correct behaviour when a user routine is what was
meant. What is missing is the helper, not the guard.

## Why the obvious fix is the wrong one

Not "pull `builtin` on bare". Verified rather than assumed — `uses builtin`
under `--esp-profile=bare` fails on both chips:

    pascal26:1161: error: undefined variable (PXXVarBinOp)     in builtin.pas
    pascal26:1724: error: undefined variable (PxxSciDigits17)  in builtin.pas

`pasparser_prog.inc:1039` says of `builtin` that ESP *"cannot compile [it] at
all"*, and that comment is **TRUE** — checked, because a comment and the code
disagreeing is the case where one of them is wrong and you do not know which.
`PxxSciDigits17` is declared in `builtinheap.pas`, so the two are companion-unit
breakage rather than anything about the ISA, but the effect stands.

Nor is the size policy wrong: bare deliberately carries no RTL because
`softfloat` alone is ~54–64KB of flash and the typical MCU program has no float
in it. See [[feature-a-complete-the-builtin-unit-on-the-esp-class-targets]]
(done, and about the IDF profile, which is why it did not reach this).

## The fix, and what makes it cheap

A minimal `__pxxAssert` needs `AnsiString`, `+`, `WriteLn` and `Halt`, and **all
four already work on bare** — measured, not assumed:

    program s; var x: AnsiString;
    begin x := 'a'; x := x + 'b'; WriteLn(x); end.
    --target=esp32s3 --esp-profile=bare  ->  ok, code=46516B (empty: 46436B)

Eighty bytes. So a small dedicated unit carrying only `__pxxAssert` (with
`AssertErrorProc` and FPC's message shape — the message REPLACES
`Assertion failed`, position appended, `Halt(227)`), injected on demand from the
existing ESP-class token scan exactly the way `needsSoftFloat` is
(`pasparser_prog.inc:1067` scan, `:1739` injection), costs nothing to a program
with no assertion in it.

## Whatever fixes this must land a row that RUNS

`test_esp_bare.pas` contains no `Assert`, which is why 29 green assertions on
both chips did not see this. The row belongs in `test-esp-bare` — but note that
target is in ZERO tiers ([[bug-t-the-esp-bare-suite-is-in-no-tier-so-nothing-ever-runs-it]]),
so a row added there today is watched by nothing. Assert the OUTPUT under qemu
(`tools/esp_run_bare.sh`), not just that it compiles: `Assert(False)` must print
the composed message and stop, and a passing `Assert` must print nothing.

## CORRECTION, same evening, by the author — "WriteLn works on bare" was a COMPILE, not a run

The section above said *"a minimal `__pxxAssert` needs AnsiString, `+`, `WriteLn`
and `Halt`, and all four already work on bare — measured, not assumed"*, and
cited an 80-byte size delta as the evidence. **Three of the four work. `writeln`
compiles and emits nothing**, and the 80 bytes were the string, not the output.

What I actually measured was `ok:` from the compiler. On a profile whose only
evidence of having run is what appears on a wire, that is not a result — and the
word "measured" beside it made the claim read as the checked part. This is the
same shape as the size ticket I corrected an hour earlier, pointed at myself.

**The device says it plainly.** A program that writes `MMIO-A`, then `WriteLn`,
then `MMIO-C` prints `MMIO-A` and `MMIO-C` on both chips and nothing between
them: the program RUNS, execution continues past the `writeln`, and the output
is simply gone. So it is a silent no-op and not a crash — which is why a build
check could never have separated them.

**And it is INTENDED and already written down**, which I should have read before
claiming the opposite: `docs/targets/esp32.md:70` — *"`writeln`/`readln` are
intentionally no-ops — there is no console. Output goes through your own UART
writes."* `test/test_esp_bare.pas` has hand-rolled `PByte($60000000)^ :=` since
the day it was written, and the whole suite does the same.

**Consequence for the fix, and it is not cosmetic.** A helper that reuses
`builtin`'s body compiles on both chips and prints NOTHING when the assertion
fires — a silent `Halt(227)`. That is the worst available outcome for an
assertion: strictly less informative than the compile error this ticket is
about, because at least the compile error was loud. The helper has to write the
composed message to the UART0 TX FIFO itself (`defs.inc:1847`: *"UART0 FIFO is
MMIO at 0x60000000 on both"*), which is also what the docs tell every bare user
to do by hand.

**I know both of those because I wrote the naive version first and ran it.** The
compile-only version passed every check I had — both chips built, the no-assert
program stayed byte-identical to the canary baseline — and produced no output at
all on the device.
