---
track: P
prio: 10
---

# `System.Integer` is SmallInt in FPC, LongInt in pxx

- **Type:** compat (FPC parity) — tag: compat
- **Track:** P — Pascal frontend
- **Found:** 2026-08-20 (frank1-ACP), while adding the `System.`-qualified TYPE
  parse for [[feature-pascal-corpus-generics]].

## The divergence

```pascal
{$mode objfpc}
WriteLn(SizeOf(System.Integer), ' ', SizeOf(Integer));
```

fpc 3.2.2 x86-64 prints `2 4`. pxx prints `4 4`.

FPC's `system` unit really declares `Integer = smallint`; the 4-byte `Integer`
every objfpc program uses comes from the *mode*, which redeclares it. So in FPC
the qualifier picks a DIFFERENT TYPE, and `System.Integer(x)` is a 16-bit
truncating cast. pxx has one `Integer` and no System namespace to differ from —
`System.X` is stripped and resolves to the builtin (see `EatSystemQualifier`).

`SizeOf(System.LongWord)`, `System.Boolean`, `System.Char` etc. agree in both;
`Integer` is the one name FPC's mode shadows.

## Does it matter

Only for a value outside -32768..32767 cast through the qualified spelling. The
one real-world use found so far is rtl-generics' `TCompare.UInt8`:

```pascal
Result := System.Integer(ALeft) - System.Integer(ARight);
```

whose operands are bytes, so both compilers give the same answer.

## Why this is compat and not a `bug-`

It is a *silent* difference in a cast width, which is the shape that normally
gets promoted out of the compat tag. It stays here because the promotion rule is
about pxx computing a wrong value for code whose meaning is unambiguous — and
here FPC's own answer is the surprising one (a program written against
mode-objfpc's `Integer` gets 16 bits it did not ask for). Reproducing it would
mean giving pxx a second `Integer` type reachable only through a namespace it
otherwise does not have. Prio is low deliberately; raise it if a corpus program
is found that truncates differently under the two compilers.

## If it is ever done

`EatSystemQualifier` is the single place that strips the qualifier, so a
System-scope type table would hook in there — not in the two dispatches that
call it.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick`. Coverage today:
`test/test_fpc_compat_batch.pas` asserts the `System.LongWord` identities and
carries a comment pointing here.
