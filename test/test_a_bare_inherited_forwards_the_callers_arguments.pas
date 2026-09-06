{ `inherited;` with NO method name calls the ancestor's method of the same name
  and passes THIS method's own parameters to it, unchanged. pxx called it with
  zero arguments and answered `inherited call argument count mismatch` on the
  universal Delphi constructor idiom (fpc testsuite tclass3).

  ONLY the bare form forwards, and that is measured rather than assumed: fpc
  3.2.2 refuses `inherited Create;` against `constructor Create(LongInt;
  ShortString)` with "Wrong number of parameters specified", while `inherited;`
  in the same body compiles and passes the caller's arguments. Naming the method
  makes it an ordinary call with an ordinary argument list.

  The zero-parameter rows are the controls that the forward did not change the
  case that already worked -- a destructor and an argumentless virtual method
  are where `inherited;` is written most often. The `var` row is the one that
  would break quietly if the forward copied instead of passing the symbol. }
{$mode delphi}
program test_a_bare_inherited_forwards_the_callers_arguments;

type
  TA = class
  public
    constructor Create(k1: LongInt; k2: ShortString);
    destructor Destroy; override;
    procedure NoArgs; virtual;
    procedure Bump(n: LongInt); virtual;
    procedure Grow(var n: LongInt); virtual;
    procedure Three(a: LongInt; const b: ShortString; c: Boolean); virtual;
  end;

  TB = class(TA)
  public
    constructor Create(l1: LongInt; l2: ShortString);
    destructor Destroy; override;
    procedure NoArgs; override;
    procedure Bump(n: LongInt); override;
    procedure Grow(var n: LongInt); override;
    procedure Three(a: LongInt; const b: ShortString; c: Boolean); override;
  end;

  TC = class(TB)
  public
    procedure Bump(n: LongInt); override;
  end;

constructor TA.Create(k1: LongInt; k2: ShortString);
begin WriteLn('TA.Create ', k1, ' ', k2); end;
destructor TA.Destroy;
begin WriteLn('TA.Destroy'); inherited; end;
procedure TA.NoArgs;
begin WriteLn('TA.NoArgs'); end;
procedure TA.Bump(n: LongInt);
begin WriteLn('TA.Bump ', n); end;
procedure TA.Grow(var n: LongInt);
begin n := n + 1; WriteLn('TA.Grow ', n); end;
procedure TA.Three(a: LongInt; const b: ShortString; c: Boolean);
begin WriteLn('TA.Three ', a, ' ', b, ' ', c); end;

constructor TB.Create(l1: LongInt; l2: ShortString);
begin WriteLn('TB.Create ', l1, ' ', l2); inherited; end;
destructor TB.Destroy;
begin WriteLn('TB.Destroy'); inherited; end;
procedure TB.NoArgs;
begin WriteLn('TB.NoArgs'); inherited; end;
procedure TB.Bump(n: LongInt);
begin WriteLn('TB.Bump ', n); inherited; end;
procedure TB.Grow(var n: LongInt);
begin n := n * 10; WriteLn('TB.Grow ', n); inherited; end;
procedure TB.Three(a: LongInt; const b: ShortString; c: Boolean);
begin WriteLn('TB.Three ', a, ' ', b, ' ', c); inherited; end;

procedure TC.Bump(n: LongInt);
begin WriteLn('TC.Bump ', n); inherited; end;

var
  b: TB;
  c: TC;
  v: LongInt;
begin
  b := TB.Create(7, 'seven');
  b.NoArgs;
  b.Bump(42);
  v := 3;
  b.Grow(v);
  WriteLn('after Grow ', v);
  b.Three(1, 'two', True);
  b.Free;
  c := TC.Create(9, 'nine');
  c.Bump(5);
  c.Free;
end.
