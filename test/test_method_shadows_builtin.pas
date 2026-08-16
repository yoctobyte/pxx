{ An unqualified call inside a method binds the enclosing class's own method
  (or an ancestor's) before the builtin of the same name. The soft intrinsics
  guarded themselves with `FindProc(nm) < 0`, which only sees a plain routine —
  a class METHOD is not registered under its bare name, so the builtin won:
  TFPObjectList.Remove's own `Delete(Result)` bound the builtin, whose argument
  check rejected an Integer, and lib/rtl/contnrs.pas had not compiled since it
  landed. Found by Track T.
  bug-p-a-class-method-does-not-shadow-a-builtin-of-the-same-name
  Values below are `fpc -O- -Mobjfpc`'s. }
program test_method_shadows_builtin;
{$mode objfpc}{$H+}

{ a unit-level routine shadows a builtin too — the arm that already worked, kept
  here as the control that it still does }
procedure Dispose(i: Integer); begin writeln('unit Dispose ', i); end;

type
  TA = class
    procedure Insert(i: Integer); virtual;
  end;
  TB = class(TA)
    procedure Delete(i: Integer);
    procedure SetLength(i: Integer);
    procedure Str(i: Integer);
    procedure New(i: Integer);
    function Use(i: Integer): Integer;
  end;

procedure TA.Insert(i: Integer); begin writeln('ancestor Insert ', i); end;
procedure TB.Delete(i: Integer);    begin writeln('method Delete ', i); end;
procedure TB.SetLength(i: Integer); begin writeln('method SetLength ', i); end;
procedure TB.Str(i: Integer);       begin writeln('method Str ', i); end;
procedure TB.New(i: Integer);       begin writeln('method New ', i); end;

function TB.Use(i: Integer): Integer;
begin
  Delete(i);          { own method }
  Insert(i);          { ancestor's method }
  SetLength(i);
  Str(i);
  New(i);
  Result := i;
end;

var b: TB; s: string; arr: array of Integer; p: ^Integer;
begin
  b := TB.Create;
  writeln(b.Use(7));
  b.Free;
  Dispose(3);
  { outside a method the builtins are untouched }
  s := 'abcdef';
  Delete(s, 2, 3);
  writeln(s);
  Insert('XY', s, 2);
  writeln(s);
  SetLength(arr, 3); arr[0] := 5;
  writeln(Length(arr), ' ', arr[0]);
  Str(42, s); writeln('[', s, ']');
  { NB: no `System.Dispose(p)` here -- the qualified form ALSO binds the
    unit-level routine, which is a separate pre-existing bug (filed as
    bug-p-a-system-qualified-call-binds-a-same-named-user-routine) and would
    make this test assert that bug rather than this one. }
  System.New(p); p^ := 11; writeln(p^); FreeMem(p);
end.
