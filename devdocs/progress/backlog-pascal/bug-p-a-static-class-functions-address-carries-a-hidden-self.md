---
track: P
prio: 55
type: bug
blocked-by: []
status: open
owner: ""
summary: "`@TSvc.Pick` where Pick is `class function ...; static;` yields a routine that still expects a leading Self, so casting it to a plain function pointer -- the ONLY way rtl-generics dispatches its comparers -- shifts every argument by one. Measured 2026-09-09 at binary a312307dfea3, one program, three rows: a direct call gives 107 in both compilers; through `function(A: Pointer; ASize: SizeInt)` pxx gives 119 against fpc's 107; through a cast with an EXPLICIT leading Self pxx gives 107 and fpc gives 100 -- the two compilers are exactly inverted, which is the positive control. Cause: pxx's `isStaticMethod` means `class method`, not the `static` DIRECTIVE (pasparser_decl.inc sets UMthIsStatic from isClassMethod for classes and from RecordMethodClassPrefix for records), and pasparser_proc.inc gives every one of them a Self at index 0. FPC's `static` means NO Self and a body that may not name it. This is what leaves `TComparer<T>.Default` nil on the rtl-generics rung: LookupComparer calls `TSelectFunc(LInstance.SelectorInstance)(GetTypeData(ATypeInfo), ASize)` through exactly this cast. NOT a wrong VALUE that a test would catch by reading a number -- the direct-call spelling is correct, so every ordinary use of a static method agrees with fpc."
---

# A static class function's address carries a hidden Self

**Blocks [[feature-pascal-corpus-generics]]** — `uses Generics.Defaults` compiles
and runs since `163e146eb`, and `TComparer<LongInt>.Default` answers **nil**
where fpc answers a live comparer.

## The measurement — one program, three rows

```pascal
type
  TPlainFunc = function (A: Pointer; ASize: SizeInt): Pointer;
  TSelfFunc  = function (Self: Pointer; A: Pointer; ASize: SizeInt): Pointer;
  TSvc = class
    class function Pick(A: Pointer; ASize: SizeInt): Pointer; static;
  end;
class function TSvc.Pick(A: Pointer; ASize: SizeInt): Pointer;
begin Result := Pointer(PtrUInt(ASize) + 100); end;
const
  Table: array[0..0] of Pointer = (@TSvc.Pick);
```

| spelling | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `TSvc.Pick(nil, 7)` | 107 | 107 |
| `TPlainFunc(Table[0])(nil, 7)` | **119** | 107 |
| `TSelfFunc(Table[0])(nil, nil, 7)` | 107 | **100** |

The third row is the positive control and it is exactly inverted: the cast that
is WRONG under fpc is the one that works here. So this is not a corrupted
address or a bad relocation — the routine is fine and its ARITY is one greater
than the source says.

## Cause

`pasparser_proc.inc`'s Self block gives every method a Self at index 0, "including
a STATIC (class) method, whose Self is the CLASS". That is right for an ordinary
`class function`, whose Self IS the runtime metaclass and whose FPC idiom depends
on it. It is wrong for `static`, which in FPC means the method has no Self at all
and its body may not name one.

pxx does not distinguish them: `UMthIsStatic` is set from `isClassMethod`
(`pasparser_decl.inc:8671`) for a class and from `RecordMethodClassPrefix`
(`:5423`) for a record. **The `static` directive is parsed and does not reach the
signature.**

## Why nothing has caught it

Every ordinary call is emitted by the compiler, which passes the Self it also
expects — so the direct-call row above is correct, and a test that calls a static
method and reads its answer cannot fail. The divergence needs the ADDRESS to
escape into a plain function pointer, which is exactly what a dispatch table
does and what no small test does.

## What it will cost to fix

An ABI change for every `static` method: no Self parameter, no Self argument at
every call site, and the record/class-helper arms in both the decl and the impl
Self blocks re-checked against each other
(see devdocs/dev/debugging-playbook.md, "A RULE THAT LIVES ON ONE SIDE OF A
DECLARATION/IMPLEMENTATION PAIR FAILS BY AGREEING" — this pair has now produced
two bugs in one day). The narrow alternative — keep the hidden Self and strip it
only when a static method's address is TAKEN — is a thunk per method and does not
make `Self` unavailable inside a static body, which is the other half of what
`static` means.

Not attempted here: it is an ABI change and it wants its own seat.
