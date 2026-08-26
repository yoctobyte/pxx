---
slug: compat-pascal-overload-prefers-signed-for-an-unsigned-argument
track: A
prio: 12
status: backlog
---

# Overload resolution picks the signed arm for an unsigned argument

With both arms visible, a `Cardinal` argument goes to `Int64`, where FPC sends
it to `QWord`:

```pascal
function Sig(v: Int64): AnsiString; overload;  begin Sig := 'i64';   end;
function Sig(v: QWord): AnsiString; overload;  begin Sig := 'qword'; end;
var c: Cardinal;
begin c := 5; WriteLn(Sig(c)); end.
```

| argument | pxx | fpc |
| --- | --- | --- |
| `QWord` | qword | qword |
| `Int64` | i64 | i64 |
| **`Cardinal`** | **i64** | **qword** |
| `Integer` | i64 | i64 |
| `q shl 1` (QWord expr) | qword | qword |

So only the *narrow unsigned* case differs: pxx ranks "widen to the signed 64-bit
arm" and FPC ranks "keep the signedness". Both conversions are lossless for a
Cardinal, so no value is wrong today — this is a preference, not a defect, and it
is filed as compat rather than as a bug for that reason.

## Why it is still worth recording

It becomes observable the moment the two overloads *behave* differently rather
than merely accepting different types — which is exactly the situation in
`bug-b-inttostr-of-a-qword-above-2-63-renders-negative`. Once
`IntToStr(QWord)` lands beside `IntToStr(Int64)`, a `Cardinal` argument will
still route to the Int64 arm here and to the QWord arm under FPC. For
`IntToStr` the rendered digits are identical either way, so nothing breaks; for
a user's own pair of overloads it could pick the other function.

## Scope

The rule to match is FPC's: among candidates reachable by widening, prefer one
that preserves signedness over one that does not. Narrow-signed→`Int64` and
narrow-unsigned→`QWord` both then fall out.

Belongs behind `--strict-overload` if it turns out to move any existing
resolution, and unconditionally if it does not — preferring the same-signedness
arm is the better default independently of FPC.

## Found by

An integer-arithmetic differential, while confirming that
`bug-b-inttostr-of-a-qword-above-2-63-renders-negative` was a missing overload
rather than a resolution failure. It is a resolution failure — just not that one.
