---
summary: "every 32-bit target: a VIRTUAL method taking an Int64 AND returning an Int64 returns garbage (arm32/riscv32) or crashes (i386) — hits TStream.Position, and riscv32 is ESP32"
type: bug
track: A
prio: 85
owner: claude-b-night2
---

# 32-bit: a virtual method with a 64-bit parameter **and** a 64-bit result is miscompiled

- **Type:** bug — Track A (32-bit backends / virtual-call ABI)
- **Status:** done
- **Opened:** 2026-08-04
- **Found by:** Track B, cross-target differential sweep of the lib tests
  (`lib_classes` SIGSEGVs on i386). Reduced from `TMemoryStream.Position` to
  three lines with no RTL involvement.

## Repro

```pascal
program v3;
type
  TB = class
  public
    function V(const x: Int64): Int64; virtual;
    function S(const x: Int64): Int64;          { same signature, not virtual }
  end;
function TB.V(const x: Int64): Int64; begin V := x + 1; end;
function TB.S(const x: Int64): Int64; begin S := x + 1; end;
function Free1(const x: Int64): Int64; begin Free1 := x + 1; end;
var b: TB;
begin
  b := TB.Create;
  writeln(Free1(5));   { plain function }
  writeln(b.S(5));     { static method  }
  writeln(b.V(5));     { VIRTUAL method }
end.
```

| target | plain fn | static method | **virtual method** |
| --- | --- | --- | --- |
| x86-64 | 6 | 6 | 6 |
| aarch64 | 6 | 6 | 6 |
| **i386** | 6 | 6 | **4647785218550267910** |
| **arm32** | 6 | 6 | **94489280518** |
| **riscv32** | 6 | 6 | **94489280518** |

`94489280518` is `6 + 22 * 2^32`: **the low 32 bits are correct and the high 32
bits are garbage.** On i386 the corruption is total, and in richer shapes
(`TMemoryStream`) it segfaults deterministically.

## It needs BOTH halves 64-bit, and it needs the call to be virtual

Narrowed one axis at a time; each row is a separate measurement:

| shape | 32-bit targets |
| --- | --- |
| virtual, `Int64` result, **no** params | ok |
| virtual, `Int64` param, `Integer` result | ok |
| **virtual, `Int64` param AND `Int64` result** | **WRONG** |
| non-virtual method, `Int64` param and result | ok |
| plain function, `Int64` param and result | ok |

So neither a 64-bit argument nor a 64-bit return is enough on its own — it is
the combination, through the vtable. That points at argument/result slot
allocation in the virtual-call path rather than at 64-bit handling generally,
which is otherwise fine on these targets.

The enum parameter in the original `Seek(0, soCurrent)` is **not** part of it —
a two-parameter version without the enum fails identically.

## Why urgent

1. **Silent on arm32 and riscv32.** Wrong number, no error. On i386 it is
   usually a crash, which is the *lucky* case.
2. **riscv32 is ESP32.** The user has named ESP32 a prime intended target
   (Track S), and its whole peripheral/IDF surface is object-oriented.
3. **It is already in the RTL.** `TStream.GetPosition` is
   `Result := Seek(0, soCurrent)` and `Seek` is `virtual` with exactly this
   signature — so `TMemoryStream.Position` returns garbage on arm32
   (`4294967296` for a position of 4) and segfaults on i386. Any stream code
   is affected on every 32-bit target.
4. It is **invisible to the current gates**: `lib-test` runs x86-64 only, and
   the cross matrix (`--tier full`, green on xeon) does not run the lib tests.

## Coverage gap this exposes

`lib_classes` fails on i386 and arm32 today and nothing reports it. The sweep
that found this — build every `test/lib_*.pas` for i386/arm32/aarch64 and diff
the output against the x86-64 run, which lib-test already proves green — is
cheap and found several more divergences (`lib_ecdsa_p256` segfaults on arm32,
`lib_directory` differs on arm32/aarch64). Worth folding into Track T's matrix;
filed separately as the sweep turns up causes.

Caveat for whoever runs it: these were measured under **qemu-user**, which can
itself misbehave for threads and some syscalls, so a network- or thread-using
test differing is not by itself evidence. This particular bug is not affected —
it reduces to arithmetic with no syscalls at all.


---

## Root cause (measured, FIXED 2026-08-05)

Every 32-bit backend's `IR_VIRTUAL_CALL` pushed **one word per argument**,
unconditionally:

```pascal
while argNode <> -1 do
begin
  IREmitNodeArm32(IRA[argNode]);
  EmitI32($E92D0001);            { push {r0} }
  Inc(nArgs);
  argNode := IRB[argNode];
end;
```

A by-value 64-bit parameter is **two** words. The direct-call and indirect-call
paths in the same files already knew that — each has a ladder handling Int64,
double, sets and 5-8 byte records — and the virtual path never grew one. So the
high half of an `Int64` argument was dropped and the callee read garbage for it.

That explains both halves of the ticket's puzzle exactly:

- **why it needed a 64-bit RESULT too** — with an `Integer` result the garbage
  high half was truncated away on the way back, so the damage was invisible;
- **why non-virtual calls were fine** — they take the ladder-bearing path.

The fix mirrors the direct path's Int64 (and double) cases into each virtual
path. Duplication, deliberately and with a note: unifying the ladders is filed
as `feature-a-unify-32bit-call-argument-marshalling`, and this drift is exactly
the argument for it.

### Two things measurement caught that reasoning would not have

1. **arm32: `j` already held the VMT slot.** Using it as the new word counter
   made a *no-argument* virtual method dispatch through the wrong slot — the
   `A=7` case broke while the case being fixed started passing. Renamed to
   `wid`.
2. **i386: the push order is `hi` then `lo`.** The opposite was tried first, on
   the reasonable theory that this path's leftmost-DEEPEST layout should mirror
   the pair too. It produced `21474836481` = `5*2^32 + 1` — the halves swapped.
   Running it cost one build; deriving it would have cost more and might still
   have been wrong.

## Verification

| | x86-64 | aarch64 | i386 | arm32 | riscv32 |
| --- | --- | --- | --- | --- | --- |
| the ticket's three-line repro | 6 | 6 | **6** | **6** | **6** |
| `TMemoryStream.Position` | 8 / 4 | 8 / 4 | **8 / 4** | **8 / 4** | **8 / 4** |

`TMemoryStream.Position` previously segfaulted on i386 and answered
`4294967296` on arm32; all five now match FPC.

- `test/test_virtual_int64_param_and_result.pas`, wired into `make test`,
  covers all four axes the ticket narrowed (64-bit result alone, 64-bit arg
  alone, both, and the non-virtual control) and passes an argument that
  actually uses its high word (`10000000000`) so a dropped half cannot
  coincidentally pass. PASS on x86-64, i386, arm32, riscv32, aarch64.
- self-host fixedpoint converged in one round; `tools/gate.sh quick` GREEN;
  `make test` GREEN.
- **`tools/lib_cross_sweep.sh`, A/B against the pinned stable.** The full run
  kept being killed part-way, so it was covered in two halves:
  - `lib_a*`–`lib_k*`: exactly two entries went away — **`lib_classes` on arm32
    AND i386**, the tests this ticket says the bug breaks — and nothing new.
  - `lib_l*`–`lib_z*`: run twice, once per compiler. Two entries move
    (`lib_platform_esp` on all three targets, `lib_sockets` on aarch64) and
    **both are flaky**: running each 3x and 2x respectively with the PINNED
    compiler and with this one flips them independently of which compiler
    built them. Network/environment tests under qemu, which this sweep's own
    header warns about.

  Two measurement traps worth recording, both self-inflicted:
  1. A first A/B looked like a large regression. The baseline file had been
     built from a `tail -25` of an earlier run, so it held 6 lines of a 37-line
     report. **Compare full outputs.**
  2. `comm -23` against a TRUNCATED run reports every not-yet-reached test as
     "fixed". Restrict the comparison to the range the run actually covered.

## A second bug found by looking for it

The follow-up ticket's prediction — that the virtual paths, having had no
ladder at all, are probably also wrong for a by-value `set` — was tested rather
than left as a guess, and it was right:

```pascal
function CountSet(const s: TES): Integer; virtual;   { TES = set of TE }
...
b.CountSet([eA, eC, eD])
```

| | FPC | x86-64 | aarch64 | i386 | arm32 | riscv32 |
| --- | --- | --- | --- | --- | --- | --- |
| before | 3 | 3 | 3 | **1** | 3 | **0** |
| after | 3 | 3 | 3 | 3 | 3 | 3 |

arm32 was right by accident: it passes sets by address on both call paths, so
the missing ladder entry cost it nothing. A by-value 5-8 byte record was fine
everywhere for the same reason.

Fixing riscv32 also needed its virtual path to grow the **>8-word stack spill**
the direct path already had — `Self` plus a 32-byte set is nine words, and the
old code refused outright (`virtual call with more than 8 parameter words not
supported`). The refusal was honest, but a shape this ordinary should not hit
it.

Both are covered by the same regression test.

## Not addressed here

The ticket's "coverage gap" section — folding the lib cross sweep into Track T's
matrix — is untouched and still worth doing. `lib_ecdsa_p256` on arm32,
`lib_directory`, and the remaining 34 sweep divergences are separate causes.

## Log
- 2026-08-05 — resolved, commit fd99c8836.
