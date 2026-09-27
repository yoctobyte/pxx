---
slug: bug-a-xtensa-cpu-lx6-is-a-no-op-and-its-premise-is-wrong
track: A
type: bug
prio: 35
status: open
owner: ""
created: 2026-09-28
blocked-by: []
summary: "--xtensa-cpu=lx6 and its alias --xtensa-soft-divide are no-ops, and the reason they exist is false. (a) The ESP32 classic LX6 DOES have the hardware divide option: Espressif's own xtensa-esp32-elf-gcc emits `quos`/`rems` for a/b and a%b at -O2, and xtensa-esp32-elf-as assembles `quos` for esp32 -- while compiler.pas, defs.inc, pasparser_prog.inc and builtinheap.pas all state it does not. defs.inc already contradicted itself: the XtensaSoftMulHigh comment says all eight qemu-xtensa cores DO have the divide option. (b) The flags are dead in practice: with a genuine runtime 32-bit div/mod (divisor loaded through a pointer so it cannot fold), --target=esp32 produces a BYTE-IDENTICAL object with and without the flag and registers no __pxx_divsi3. (c) The bigger finding behind (b): pxx emits no quos/quou/rems/remu on ANY xtensa target -- esp32, esp32s2, esp32s3 -- so the four codegen sites that read XtensaSoftDivide (ir_codegen_xtensa.inc:3161-3176) are never reached and the documented default of 'native quos/rems' never happens. Where div/mod ARE lowered is NOT established. div+mod cost 384 B of .text on all three xtensa targets and 368 B on esp32c3 (riscv32), so something substantial is emitted; whether it is a software routine that should be a 3-byte quos, or a div-by-zero check plus a hardware divide my byte search cannot see, is the open question. Correctness is not in question here -- results are right -- so this is a performance and dead-code ticket, plus four wrong comments now corrected."
---

# --xtensa-cpu=lx6 is a no-op, and the LX6 does have a divider

- **Type:** bug — Track A
- **Status:** open. The wrong comments are corrected; the flag is left in place
  and harmless pending a decision.
- **Opened:** 2026-09-28. Found from frankd-90's observation, relayed by
  frankuser, that `--xtensa-soft-divide` and `--xtensa-cpu=lx6` give an object
  byte-identical to the default for `writeln(a div b, a mod b)`.

## What was asked and what is true

frankd-90 saw byte-identical objects and `quos`/`rems` still emitted. The first
half reproduces. The second half does not: nothing emits `quos`/`rems`.

1. **The premise is false.** The ESP32 classic LX6 has the divide option:

   ```
   $ xtensa-esp32-elf-gcc -O2 -c d.c     # int f(int a,int b){return a/b;}
   3:  d22230    quos  a2, a2, a3
   b:  f22230    rems  a2, a2, a3
   $ printf '\tquos a2,a2,a3\n' | xtensa-esp32-elf-as     # accepted
   ```

   Four places in the tree said otherwise (`compiler.pas` at the flag parse,
   `defs.inc` on `XtensaSoftDivide`, `pasparser_prog.inc` at the helper
   registration, `builtinheap.pas` above the helpers). All four are corrected in
   the same commit as this ticket, since the measurement is cheap to redo and the
   claim is load-bearing for the flag's existence.

   The tree already contradicted itself: `defs.inc`'s `XtensaSoftMulHigh`
   comment records that all eight qemu-xtensa cores "DO have the divide option",
   which cannot hold for a part that lacks one.

2. **The flag changes nothing.** `div32.pas` — `b := p^` from an arbitrary
   address so the divisor cannot be folded, operands and results all 32-bit
   `Integer`, results consumed:

   | build | quos | quou | rems | remu | object sha12 |
   |---|---|---|---|---|---|
   | `--target=esp32` | 0 | 0 | 0 | 0 | `53ccaef80f8e` |
   | `--target=esp32 --xtensa-cpu=lx6` | 0 | 0 | 0 | 0 | `53ccaef80f8e` |

   Byte-identical, and `__pxx_divsi3`/`__pxx_modsi3` are absent from the symbol
   table in both, although `pasparser_prog.inc` registers them under the flag.

3. **No xtensa target emits a hardware divide.** Same program, same search:

   | target | div+mod cost | quos/quou/rems/remu |
   |---|---|---|
   | esp32 | 384 B | 0 |
   | esp32s2 | 384 B | 0 |
   | esp32s3 | 384 B | 0 |
   | esp32c3 (riscv32, control) | 368 B | n/a |

   `esp32s3` is the LX7 part whose `quos`/`rems` the default is documented to
   keep, and it emits none either. So `ir_codegen_xtensa.inc:3161-3176` — the
   only four sites that read `XtensaSoftDivide`, and the only four that call
   `xtensa_quos`/`quou`/`rems`/`remu` — appear unreachable, and the flag is dead
   because the code it toggles is dead.

## What is NOT established

**Where `div`/`mod` actually get lowered.** The 384 B says something
substantial is emitted, but I did not identify it, and I am not going to guess
in a ticket. Candidates not ruled out:

- `EmitIDivMod64Xtensa`/`EmitUDivMod64Xtensa` (`ir_codegen_xtensa.inc:1145,1201`),
  reached via the 64-bit check at line 1269 — an inline software divide. I
  tested the obvious way this could capture 32-bit code (`writeln`'s argument is
  `Int64`, so `writeln(a div b)` may widen the divide) by storing into `Integer`
  locals first; that did not change the result, so if this is the path it is not
  reached by argument widening.
- A div-by-zero check plus error machinery accounting for most of the 384 B,
  with the divide itself somewhere my search cannot see.

## Instrument notes, because three instruments lied here

Worth reading before redoing any of this — I drew a wrong conclusion from each
of the first three before validating them.

- **`objdump -d` on a pxx executable shows nothing.** pxx emits executables with
  **no section header** (`file` says so), so `objdump -d` prints three lines and
  no code. My first "zero `idiv` on x86-64" reading was meaningless.
- **xtensa `.o` disassembly desynchronises.** Xtensa puts literal pools inline
  in `.text`, so linear disassembly walks into data and prints `ill` and stray
  `.byte 0xff`. Mnemonic greps over it are worthless; the register-exact byte
  search (`quos a2,a2,a3` = `30 22 d2`) is what to use.
- **Validate the byte search on a positive control.** gcc's `d.o`, known to
  contain both, reads `quos=1 rems=1`. Without that step a blind search and an
  absent instruction look identical — the same guard-polarity trap as
  `esp_flash.sh`'s `ESP-ROM` row.
- **The obvious test program folds.** `a := 1000; b := 7; writeln(a div b)`
  computes at compile time and emits no divide at all; so does taking the
  operands from an inlinable helper, and so does a `for i := 1 to 3` loop with
  constant bounds. The divisor must come from somewhere the compiler cannot
  see — a load through a pointer works. A size diff against an add/sub twin
  confirms the divide is really in the object (384 B) before anything is
  concluded from its absence.
- **`--emit-obj` is x86-64 only** and refuses a program with no C-convention
  symbol; a `cdecl` function in a program still gets dead-stripped if nothing
  calls it, leaving an object with only `app_main` and no divide to find.

## Decision needed

Three options, in my order of preference:

1. **Find the real lowering and emit `quos`/`rems` on the parts that have them**
   (all of esp32/s2/s3, and the LX6 included). Integer division on ESP then
   costs one instruction instead of whatever the 384 B is. This is the only
   option that turns the finding into a win.
2. **Delete the flags and the helpers.** Nothing reaches them, the part they
   were written for does not need them, and dead capability flags invite exactly
   the wrong conclusion the next person draws.
3. **Document them as no-ops** and leave them. Cheapest, and what the corrected
   comments currently do.

Not urgent: results are correct today, so this is speed and dead code, not
miscompilation.
