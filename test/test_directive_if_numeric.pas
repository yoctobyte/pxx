program TestDirectiveIfNumeric;

{$mode objfpc}

{ PXX_VERSION is a compiler preset valued define (= 26). Exercise numeric {$IF}
  with every relational operator, defined() still working, and the FPC-style
  defined()+comparison header pattern. }

{$if PXX_VERSION >= 26}
const A = 1;
{$else}
const A = 0;
{$endif}

{$if PXX_VERSION >= 27}
const B = 1;
{$else}
const B = 0;
{$endif}

{$if PXX_VERSION = 26}
const C = 1;
{$else}
const C = 0;
{$endif}

{$if PXX_VERSION <> 26}
const D = 1;
{$else}
const D = 0;
{$endif}

{$if PXX_VERSION < 26}
const E = 1;
{$else}
const E = 0;
{$endif}

{$if PXX_VERSION <= 26}
const F = 1;
{$else}
const F = 0;
{$endif}

{$if PXX_VERSION > 26}
const G = 1;
{$else}
const G = 0;
{$endif}

{$if defined(PXX_VERSION)}
const H = 1;
{$else}
const H = 0;
{$endif}

{$if defined(PXX_VERSION) and (PXX_VERSION >= 26)}
const I = 1;
{$else}
const I = 0;
{$endif}

begin
  writeln(A);
  writeln(B);
  writeln(C);
  writeln(D);
  writeln(E);
  writeln(F);
  writeln(G);
  writeln(H);
  writeln(I);
end.
