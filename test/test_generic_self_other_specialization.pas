{ A reference to a DIFFERENT specialization of the SAME template, from inside
  that template's own body: `FOther: TOuter<ShortInt>` inside `TOuter<T>`.

  Three cases sit in one class body and only one was broken:

    FBox:   TBox<ShortInt>    a different TEMPLATE          -- always worked
    FSelf:  TOuter<T>         same template, same args      -- always worked
    FOther: TOuter<ShortInt>  same template, DIFFERENT args -- the defect

  WHY THE THIRD HAD NO OWNER. Each template's Delphi-surface desugar sweeps the
  token stream from its OWN end forward, so TBox's sweep collapses TBox<ShortInt>
  inside TOuter's body before TOuter is captured. TOuter's own sweep starts after
  its own tokens, deliberately: `TOuter<T>` in there means the specialization
  being built and must not become an alias. `TOuter<ShortInt>` fell between the
  two. SpecializeToBuffer then rewrote the bare name to the specialization being
  built while SelfSpecGroupEnd correctly declined to drop the argument list, and
  the output was `TOuter$LongInt<ShortInt>` -- reported as `expected ':' before
  '>'`, an internal minted name leaking at the user.

  Fixed by NORMALISING THE SURFACE at capture: the mode-Delphi spelling gets the
  `specialize` keyword the arena machinery already keys on, rather than a second
  recognizer growing downstream. The objfpc arm in uselfspec.pas is the control
  -- it always worked, and both arms must now print the SAME row.

  FPC 3.2.2 compiles NEITHER arm (`Syntax error, "identifier" expected but ";"
  found`), in mode delphi and mode objfpc alike. Us accepting what FPC rejects
  is not a defect; the claim here is that our two surfaces agree with each other
  and that FOther really is a second specialization -- which is what the two
  SizeOf columns say and nothing else in the row can.

  NOT covered, and refused with a diagnostic rather than mis-compiled: swapped
  parameters, `TPair<V, K>` inside `TPair<K, V>`. Specializing either needs the
  other declared first, and pxx says so --
  bug-p-a-generic-cannot-hold-a-parameter-swapped-specialization-of-itself.
  bug-p-a-different-specialization-of-the-same-template-inside-its-own-body }
program test_generic_self_other_specialization;
{$MODE DELPHI}

uses uselfspec, SysUtils;

type
  TBox<T>   = class V: T; end;
  TOuter<T> = class
    V: T;
    FBox:   TBox<ShortInt>;
    FSelf:  TOuter<T>;
    FOther: TOuter<ShortInt>;
  end;

var
  o: TOuter<LongInt>;
  delphiArm: AnsiString;
begin
  o := TOuter<LongInt>.Create;
  o.V := 1000000;
  o.FOther := TOuter<ShortInt>.Create;
  o.FOther.V := 7;
  o.FSelf := o;
  o.FBox := TBox<ShortInt>.Create;
  o.FBox.V := 3;
  delphiArm := IntToStr(o.V) + ' ' + IntToStr(o.FOther.V) + ' ' +
               IntToStr(o.FSelf.V) + ' ' + IntToStr(o.FBox.V) + ' ' +
               IntToStr(SizeOf(o.FOther.V)) + ' ' + IntToStr(SizeOf(o.V));
  writeln(delphiArm);
  writeln(ObjfpcArm);
  if delphiArm = ObjfpcArm then writeln('surfaces agree')
  else writeln('FAIL surfaces differ');
end.
