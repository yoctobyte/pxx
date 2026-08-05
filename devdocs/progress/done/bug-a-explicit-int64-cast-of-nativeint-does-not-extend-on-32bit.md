---
summary: "On i386/arm32 the EXPLICIT cast Int64(n) where n is NativeInt/NativeUInt reinterprets 8 bytes instead of extending 4 — Int64(5) is 4294967301. The implicit widening q := n is correct, which is why it hid"
type: bug
track: A
prio: 70
owner: claude-A
---

# `Int64(x)` of a `NativeInt` does not extend on 32-bit targets

- **Type:** bug — Track A (type conversion / codegen, 32-bit targets)
- **Status:** done
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

## Resolution (2026-08-05)

One asymmetric condition in the builtin-cast lowering (`compiler/ir.inc`,
AN_CAST `-1`/`-3` arm). That arm has two tests:

- **cast-side** — "is the cast TARGET 64-bit?" — correctly gates
  `tyNativeInt`/`tyNativeUInt` on `TypeSize(castTk) = 8`, with a comment
  explaining exactly why (`bug-nativeuint-cast-widens-load`).
- **source-side** — "is the OPERAND already 64-bit, so no widen is needed?" —
  listed `tyNativeInt`/`tyNativeUInt` **unconditionally**.

On a 32-bit target a `NativeInt` is four bytes, so `Int64(n)` matched the
source-side "already wide" test, skipped the widening `+ 0` binop, and fell
through to the in-place retag — which turns the operand's 4-byte load into an
8-byte one and drags in the adjacent storage. The fix makes the source-side test
apply the same `TypeSize(...) = 8` rule as the cast-side test four lines above
it. The two were always meant to be symmetric; only one of them was.

That also explains cleanly why the IMPLICIT form was correct and hid this:
`q := n` never reaches this arm at all.

**Checked the emitted extend, not just the output** — the ticket asked for this
explicitly, and it is the right ask:

    i386   : load_sym n (tk=15 NativeInt) ; const 0 (tk=13) ; binop + (tk=13)
    x86-64 : load_sym n retagged tk=13 in place, NO binop

So the widen really is emitted on 32-bit, and is correctly still absent on
64-bit, where `NativeInt` genuinely is 8 bytes and a retag is right — no
regression and no wasted instruction there.

**Verified.** The ticket's repro matches x86-64 on i386, arm32 and riscv32
(riscv32 had it too, unmentioned in the ticket). C's `clock()` through `crtl`
returns plausible values with a non-negative delta on i386 and arm32.
`tools/gcc_diff_probe.sh` run on all four targets with the FIXED compiler and
diffed against the same run on `pinned`: **no new divergences anywhere**, and
the counts moved strictly down — i386 and arm32 each 4 known -> 3 known,
aarch64 1 NEW -> 0.

**Do not read those improvements as this fix's doing.** `pinned` lags HEAD by
every commit since the last blessing, so pinned-vs-HEAD measures the whole
delta, not one hunk. Isolated properly by building the compiler with and
without ONLY this hunk and comparing emitted binaries:

    x86-64  : byte-IDENTICAL
    aarch64 : byte-IDENTICAL
    i386    : differs   (the widen is emitted)
    arm32   : differs
    riscv32 : differs

So this change is provably a no-op on 64-bit targets — exactly as the
`TypeSize(...) = 8` reasoning predicts — and the aarch64 probe improvement
(`integer-promotion-in-comparison`, a case containing no Int64/NativeInt cast
at all) comes from an EARLIER commit in that delta, not from here. The probe
comparison is still the check that matters for landing — "no regressions since
the last blessed compiler" — it just is not attribution.

Locked in as `test/test_int64_cast_of_nativeint.pas`: `NativeInt`/`NativeUInt`,
positive and negative, the amplifying `* 1000000` shape, the `NativeInt` record
fields `__pxx_clock` actually uses, and a `Pointer` cast to hold the
already-correct PAL path in place. Identical on i386/arm32/aarch64/riscv32 and
byte-identical to FPC.

### Handover, not done here

The Track B workaround in `lib/rtl/pxxcio.pas` is **not** reverted by this
commit — that file is Track B's lane. Filed as
`task-b-revert-pxxcio-clock-int64-cast-workaround` with the measurement that
makes it mechanical (the idiomatic one-liner gives `1234567890` on x86-64, i386
and arm32 with the fixed compiler).

**That ticket carries an ordering hazard worth repeating here:** Track B builds
with `$(PXX_STABLE)` = `pinned`, and this fix is NOT pinned yet. Reverting the
workaround before `make pin` moves would produce a lib built by a compiler that
still has the bug. The revert must wait for the pin.

## Log
- 2026-08-05 — resolved, commit ebc6f2fd3.
