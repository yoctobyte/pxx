program test_system_qualified_intrinsic;
{$mode objfpc}{$H+}

{ bug-p-a-system-qualified-call-binds-a-same-named-user-routine.

  `System.X` is THE documented way to shadow an intrinsic deliberately and still
  reach the original, and FPC code uses it routinely. Every soft intrinsic wrote
  its own `FindProc(nm) < 0` shadow guard and none of them consulted the
  qualifier, so the escape hatch did not escape. Ten shapes were wrong, across
  BOTH dispatch sites — the statement path (Delete, Insert, SetLength, Str, Inc,
  Move, Dispose) and the expression path (Length, Copy, Ord) — and three of them
  failed SILENTLY: `System.Inc(n)`, `System.Dispose(p)` and `System.Ord('A')`
  called the user routine and skipped the intrinsic's effect entirely, rather
  than reporting anything.

  Every expected value here is `fpc -O- -Mobjfpc`'s own output.

  The controls matter as much as the fixes: a shadowed intrinsic must STILL be
  shadowed when the call is unqualified — that is the feature the guards exist
  for, and the class-method half of it is what
  bug-p-a-class-method-does-not-shadow-a-builtin-of-the-same-name added. }

procedure Delete(i: Integer); begin writeln('user Delete ', i); end;
procedure Insert(i: Integer); begin writeln('user Insert ', i); end;
procedure SetLength(i: Integer); begin writeln('user SetLength ', i); end;
procedure Str(i: Integer); begin writeln('user Str ', i); end;
procedure Inc(x: Integer); begin writeln('user Inc ', x); end;
procedure Move(x: Integer); begin writeln('user Move ', x); end;
procedure Dispose(i: Integer); begin writeln('user Dispose ', i); end;
function Length(x: Integer): Integer; begin writeln('user Length ', x); Length := 99; end;
function Copy(x: Integer): Integer; begin writeln('user Copy ', x); Copy := 98; end;
function Ord(x: string): Integer; begin writeln('user Ord ', x); Ord := 97; end;

type
  PI = ^Integer;

  { A class whose own methods shadow the same intrinsics: the unqualified call
    inside a method must bind the METHOD, and `System.X` must still get past it. }
  TShadower = class
    procedure Delete(i: Integer);
    procedure Run;
  end;

procedure TShadower.Delete(i: Integer);
begin writeln('method Delete ', i); end;

procedure TShadower.Run;
var s: string;
begin
  s := 'abcdef';
  Delete(4);                      { the METHOD, not the intrinsic }
  System.Delete(s, 2, 3);         { the intrinsic, past the method }
  writeln('in-method s = ', s);
end;

var
  s, t: string;
  n, a, b: Integer;
  p: PI;
  sh: TShadower;
begin
  { --- the unqualified calls must all still reach the USER routines --- }
  Delete(7);
  Insert(7);
  SetLength(7);
  Str(7);
  Inc(7);
  Move(7);
  Dispose(7);
  writeln(Length(7));
  writeln(Copy(7));
  writeln(Ord('z'));

  { --- statement path: System.X must reach the intrinsic --- }
  s := 'abcdef'; System.Delete(s, 2, 3);    writeln('Delete    -> ', s);
  s := 'abcdef'; System.Insert('XY', s, 2); writeln('Insert    -> ', s);
  s := 'abcdef'; System.SetLength(s, 3);    writeln('SetLength -> ', s);
  System.Str(42, t);                        writeln('Str       -> ', t);

  n := 5;  System.Inc(n);                   writeln('Inc       -> ', n);
  a := 7; b := 0; System.Move(a, b, 4);     writeln('Move      -> ', b);

  System.New(p); p^ := 3;
  writeln('New       -> ', p^);
  System.Dispose(p);                        writeln('Dispose   -> freed');

  { --- expression path: same rule, a different dispatch site --- }
  s := 'abcdef';
  writeln('Length    -> ', System.Length(s));
  writeln('Copy      -> ', System.Copy(s, 2, 3));
  writeln('Ord       -> ', System.Ord('A'));

  { --- and past a class method of the same name --- }
  sh := TShadower.Create;
  sh.Run;
end.
