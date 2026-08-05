{ `.Free` off anything but a bare variable. ParseStatementAST matched the
  literal token shape `ident . Free ;`, so every selector form -- a[0].Free,
  d[0].Free, r.f.Free, h.f.Free, (o as T).Free -- fell through to ordinary
  member lookup and died as `"Free": no such member on this record/class`,
  because Free is not a member of any class the frontend knows
  (bug-p-free-and-destroy-only-work-on-a-simple-variable). FList[i].Free is
  everyday Pascal.

  Asserts the SEMANTICS, not just that it compiles: the destructor has to run,
  a user-declared Free has to win, and nil has to stay a no-op. }
program test_free_designator;
type
  TFoo = class
    n: Integer;
    destructor Destroy; override;
  end;
  TBox = record f: TFoo; end;
  THolder = class f: TFoo; end;
  TOwnFree = class
    procedure Free;
  end;
var log: string;
destructor TFoo.Destroy; begin log := log + 'd' + Chr(Ord('0') + n); inherited Destroy; end;
procedure TOwnFree.Free; begin log := log + 'U'; end;
var r: TBox; h: THolder; a: array[0..1] of TFoo; d: array of TFoo;
    o: TOwnFree; nilf: TFoo;
begin
  log := '';
  a[0] := TFoo.Create; a[0].n := 1;
  SetLength(d, 1); d[0] := TFoo.Create; d[0].n := 2;
  r.f := TFoo.Create; r.f.n := 3;
  h := THolder.Create; h.f := TFoo.Create; h.f.n := 4;
  a[1] := TFoo.Create; a[1].n := 5;

  a[0].Free;                  { static array element }
  d[0].Free;                  { dynamic array element }
  r.f.Free;                   { record field }
  h.f.Free;                   { class field }
  (a[1] as TFoo).Free;        { `(`-led statement through an as-cast }

  o := TOwnFree.Create;
  o.Free;                     { a user-declared Free must win }

  nilf := nil;
  nilf.Free;                  { nil guard: no-op, not a crash }

  h.Free;
  writeln(log);
  if log = 'd1d2d3d4d5U' then writeln('PASS') else writeln('FAIL');
end.
