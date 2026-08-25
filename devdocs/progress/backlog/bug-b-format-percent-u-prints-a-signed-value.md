---
track: B
prio: 55
type: bug
blocked-by: []
summary: "`Format('%u', [q])` on a QWord prints -1: sysutils' formatter aliases 'u' to 'd' and runs both through the signed IntToStr. FPC prints 18446744073709551615. The same line makes `%u` of Integer(-1) print -1 where FPC prints 4294967295. Filed from Track A+C+P — B owns lib/rtl."
status: backlog
owner: unassigned
---

# `Format('%u', ...)` is a synonym for `%d`

- **Track B** (`lib/rtl/sysutils.pas`, the `Format` specifier `case`).
- Found 2026-08-20 by an FPC differential probe over Format specifiers, run
  from a Track A+C+P session; filed rather than fixed because `lib/rtl` is B's
  file lane.

## Repro

```pascal
uses sysutils;
var q: QWord; i: Integer;
begin
  q := 18446744073709551615; i := -1;
  writeln(Format('%u', [q]));   { FPC: 18446744073709551615   pxx: -1 }
  writeln(Format('%u', [i]));   { FPC: 4294967295             pxx: -1 }
end.
```

## Cause

`lib/rtl/sysutils.pas`, in the specifier `case`:

```pascal
'd', 'u':
  piece := FmtIntPrec(IntToStr(FmtArgInt(args[argIdx])), hasPrec, prec);
```

One arm for two specifiers, and the shared body is signed. `%x` right below it
already does the whole job correctly — it calls `FmtArgIs32` to recover the
argument's original width from the variant tag, because `FmtArgInt` widens
everything to `Int64` on the way in. `%u` needs exactly that and does not have
it.

## Fix sketch

Split the arm. For `u`, print unsigned at the argument's own width, mirroring
what `%x` already does:

```pascal
'u':
  begin
    iv := FmtArgInt(args[argIdx]);
    if FmtArgIs32(args[argIdx]) then piece := IntToStr(Int64(LongWord(iv)))
    else piece := <unsigned 64-bit decimal of iv>;
    piece := FmtIntPrec(piece, hasPrec, prec);
  end;
```

The 64-bit half needs an unsigned decimal renderer — `IntToStr` takes `Int64`.
`StrQWord` in `compiler/builtin/builtin.pas` is the compiler-side one; sysutils
needs its own (or a `QWord` overload of `IntToStr`), which is the only real
work in this ticket.

## Two more Format gaps found by the same probe

Separate, lower value, recorded here so they are not rediscovered:

| case | FPC | pxx |
| --- | --- | --- |
| `Format('%p', [Pointer(1)])` | `0000000000000001` | `%p` (specifier unsupported, echoed literally) |
| `Format('%d', [c])`, `c: LongWord = 4294967295` | `-1` | `4294967295` |
| `Format('%c', ['A'])` | *(empty)* | `A` |

The `%d`-of-a-Cardinal row is a **compat** divergence, not a bug in the
`%u` sense: FPC passes a 32-bit unsigned as `vtInteger` and prints its bit
pattern signed, pxx passes the value and prints it as-is. pxx's answer is the
more useful one and nothing silently corrupts, so it is a deliberate-divergence
candidate rather than a fix — but it should be a DECIDED divergence, since a
program ported from FPC will see it. Same for `%c`, where FPC prints nothing at
all for a one-character string literal.

## Gate

Track B's: `make lib-test` / `make demos` with `$(PXX_STABLE)`, plus a probe
comparing every specifier against `fpc -O- -Mobjfpc` 3.2.2 — the ten-line one in
this ticket's repro is a good start and should be checked in with the fix.
