---
summary: "On i386/arm32 the EXPLICIT cast Int64(n) where n is NativeInt/NativeUInt reinterprets 8 bytes instead of extending 4 — Int64(5) is 4294967301. The implicit widening q := n is correct, which is why it hid"
type: bug
track: A
prio: 70
---

# `Int64(x)` of a `NativeInt` does not extend on 32-bit targets

- **Type:** bug — Track A (type conversion / codegen, 32-bit targets)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** `tools/gcc_diff_probe.sh --target arm32` — C's `clock()` returned
  a huge random number. Chased down through crtl to `__pxx_clock`'s Int64
  arithmetic and minimised to the cast alone.

## Repro

```pascal
program szprobe;
var n: NativeInt; u: NativeUInt; q: Int64;
begin
  writeln('SizeOf(NativeInt)=', SizeOf(NativeInt), ' Int64=', SizeOf(q));
  n := 5;
  q := n;         writeln('implicit=', q);
  q := Int64(n);  writeln('explicit=', q);
  n := -3;
  q := n;         writeln('neg-implicit=', q);
  q := Int64(n);  writeln('neg-explicit=', q);
  u := 7;         writeln('uint-explicit=', Int64(u));
end.
```

| | x86-64 | i386 | arm32 |
| --- | --- | --- | --- |
| `SizeOf(NativeInt)` | 8 | 4 | 4 |
| `implicit` (5) | 5 | **5** | **5** |
| `explicit` (5) | 5 | **4294967301** | **578446229785018373** |
| `neg-implicit` (-3) | -3 | **-3** | **-3** |
| `neg-explicit` (-3) | -3 | **8589934589** | **578446234079985661** |
| `uint-explicit` (7) | 7 | **60129542151** | **578446246964887559** |

`4294967301` is `0x1_00000005` and `8589934589` is `0x1_FFFFFFFD`: the low half
is right, the high half is **whatever happened to be in the adjacent storage**.
The cast reinterprets 8 bytes at a 4-byte location instead of sign/zero-extending.

## What is and is not affected

Measured, same programs:

- **`NativeInt` and `NativeUInt` — broken.**
- `Integer`, `LongInt` — **fine** (`Int64(i)` is correct).
- `Int64(@x)`, `Int64(p)` for a `Pointer` — **fine**, high half is 0 on both
  32-bit targets. This is the important one: the PAL passes syscall addresses as
  `Int64(@buf)` everywhere, and that path is safe.
- The **implicit** conversion (`q := n`, or `n` used in an Int64 context) is
  correct. So the bug is specifically the explicit cast syntax.

## Why it hid, and why the garbage moves

The implicit form is what most code writes, and it is correct. The explicit form
appears where someone is deliberately forcing 64-bit arithmetic — exactly the
place where the value then feeds a multiply, so the corruption is amplified
rather than truncated away.

The high half is uninitialised, so **which expression exhibits it depends on
what is on the stack**. An earlier version of this repro had `Int64(r.Sec)` on a
record field failing while `Int64(n)` on a local passed; adding one writeln
swapped them. Same trap as
[[bug-a-i386-int64-arg-high-half-uninitialized]] — a passing case proves nothing
about its neighbour. Do not accept a fix that only makes this repro pass; check
the emitted extend instruction.

## Live impact

`lib/rtl/pxxcio.pas`'s `__pxx_clock`:

```pascal
Result := Int64(ts.Sec) * 1000000 + Int64(ts.Nsec) div 1000;
```

`ts.Sec`/`ts.Nsec` are `NativeInt`, so C's `clock()` returned garbage on i386 and
arm32 — measured `6768365981682106485` and `-6010612529510736640`, with a
NEGATIVE delta between two successive calls. Any C program timing itself with
`clock()` on a 32-bit target got nonsense. `clock_gettime` itself is correct on
every target (verified separately), so this is purely the widening.

A tracked Track B workaround is in `devdocs/dev/track-b-workarounds.md`; revert
it when this closes.

## Gate

The repro above matches x86-64 on i386 and arm32; `tools/gcc_diff_probe.sh`
case `time-difftime-clock` clean on all four targets; self-host fixedpoint; cross.
