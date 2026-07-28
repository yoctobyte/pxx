---
track: A
prio: 70
type: bug
---

# Variant -> scalar unbox: silently wrong on 32-bit, and unavailable on cross targets

Two defects on the same path, found 2026-07-28 while cross-checking the new
class-into-variant boxing ([[bug-a-variant-class-boxing-missing-on-i386-aarch64]]).

## 1. Silently wrong value (i386, arm32) / wrong value (aarch64)

```pascal
program crossvar;
type
  TBox = class
    V: Integer;
  end;
var a: Variant; b: TBox; i, out_: Integer; s: AnsiString;
begin
  b := TBox.Create;
  b.V := 7;
  for i := 1 to 100 do
  begin
    a := b;
    a := 'str';
    a := 3.5;
    a := i;
  end;
  s := 'end';
  out_ := a;                 { unbox the Integer 100 }
  writeln(s, ' ', b.V, ' ', out_);
end.
```

| target | output |
| --- | --- |
| x86-64 | `end 7 100` — correct |
| aarch64 | `end 7 1` |
| i386 | `end 7 134577912` |
| arm32 | `end 7 134677360` |

The 32-bit values look like ADDRESSES (0x8055D38 and friends), so the call
result is not the payload at all. No diagnostic on any of them.

`IRLowerVariantAsScalar` (`ir.inc:~3835`) lowers this to
`VariantToInt64(const v: Variant): Int64` with a HAND-BUILT `IR_ARG` carrying
the variant's address:

```pascal
vuAddr := IRVariantAddr(argAST);
vuArg  := IRAppend(IR_ARG, vuAddr, -1, -1, 0, Ord(tyVariant));
```

That is the shape [[project_irlowercallarg_hand_built_args_landmine]] warns
about — an `IR_ARG` chain that never goes through `IRLowerCallArg`, which
presents as a cross-target codegen bug while being argument-specific. Whether
the callee expects the address (const = by reference) or a 16-byte by-value
copy is exactly the disagreement to check first. The Int64 return over an
ILP32 register PAIR is the second thing to check
([[project_32bit_truthiness_and_promotion_landmines]]).

## 2. The builtin is often not loaded at all on cross targets

The same program with the class but no string, or with `o64 := a` added:

```
error: variant unbox: VariantToInt64 builtin not loaded
```

`VariantToInt64` lives in `compiler/builtin/builtin.pas`, and whether that unit
is pulled depends on what ELSE the program uses — a string variable pulls it in,
a Double does not. So on cross targets the same source either fails to build or
builds and computes the wrong number, decided by an unrelated declaration.

## Note on how it surfaced

Before class boxing landed on i386/aarch64, `crossvar.pas` could not compile for
those targets at all (the store hit "Variant :=: this scalar type not yet
supported"). Boxing made the program compile, which is correct in itself — but
on 32-bit it now reaches this unbox and returns a wrong value silently where the
old behaviour was a build error. Worth fixing sooner for that reason.

## Gate

`make test` + cross for i386 / aarch64 / arm32, with the program above as a
test case comparing all four targets' output against x86-64's.
