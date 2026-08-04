---
summary: "every 32-bit target: a VIRTUAL method taking an Int64 AND returning an Int64 returns garbage (arm32/riscv32) or crashes (i386) — hits TStream.Position, and riscv32 is ESP32"
type: bug
track: A
prio: 85
---

# 32-bit: a virtual method with a 64-bit parameter **and** a 64-bit result is miscompiled

- **Type:** bug — Track A (32-bit backends / virtual-call ABI)
- **Status:** urgent
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
