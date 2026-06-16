# The PXX dialect

PXX compiles a **subset of Object Pascal**, plus a handful of extensions of its
own. It is not Free Pascal, but it deliberately matches FPC behaviour where it
implements something.

**For the base language — syntax, standard types, the bulk of Object Pascal —
use the [Free Pascal documentation](https://www.freepascal.org/docs.html).**
These pages do *not* re-document Pascal. They document only:

- what PXX **adds** on top of Object Pascal (the dialect extras), and
- where PXX **differs** or has **limits** worth knowing as a user.

For the hard boundaries see [Not Implemented](../not-implemented.md) and
[Not Stable](../not-stable.md). The regression suite (`make test`) is the
authoritative statement of what actually works — implementation moves faster
than prose.

## Pages

| Page | What it covers |
| --- | --- |
| [Targets & binaries](targets.md) | The six CPU targets, `--target`, static syscall-only ELF, predefined CPU symbols. |
| [Types](types.md) | Ordinals, strings (managed vs frozen), dynamic arrays, sets, records, variants, `array of const`. |
| [Routines](routines.md) | Procedures/functions, parameters, overloads, operator overloading, generics, auto-typed & inline `var`. |
| [Classes & RTTI](classes.md) | Classes, VMT, properties, metaclasses, published RTTI, `.lfm` streaming. |
| [Exceptions](exceptions.md) | `try/except`, `try/finally`, `raise`, `on E: T`. |
| [Generators](generators.md) | `; generator;`, `yield`, `for x in g` — stackful and stackless lowerings. |
| [Inline assembly](inline-asm.md) | `asm … end`, `assembler;` routines, `db` byte emission. |
| [Directives & switches](directives.md) | Source `{$…}` directives, conditional compilation, command-line switches. |

## One program, several extras

A single source blending a generic list, an overloaded operator, a managed
dynamic array, and auto-typed inline variables — compiles and runs today:

```pascal
program showcase;
uses collections;

type
  TVec = record X, Y: Integer; end;
  TIntList = specialize TList<Integer>;

operator + (a, b: TVec): TVec;
begin
  Result.X := a.X + b.X;
  Result.Y := a.Y + b.Y;
end;

var
  list: TIntList;
  i: Integer;
begin
  list := TIntList.Create;
  for i := 1 to 5 do list.Add(i * i);

  var total := 0;                  { auto-typed, declared inline }
  for i := 0 to list.Count - 1 do total := total + list.Get(i);
  writeln('sum of squares: ', total);     { 55 }

  var a: TVec; var b: TVec;
  a.X := 1; a.Y := 2; b.X := 3; b.Y := 4;
  var c := a + b;                  { overloaded operator, inferred type }
  writeln('vector sum: ', c.X, ',', c.Y); { 4,6 }
end.
```
