program test_nested_routine_depth2_capture;
{$mode objfpc}{$H+}

{ bug-a-two-level-nested-routine-cannot-capture-anything.

  A doubly-nested routine could not capture ANY enclosing variable, in any
  direction: depth-0 local, depth-0 param, depth-1 local and depth-1 param all
  failed, while depth-2-capturing-nothing and every depth-1 shape worked. Two
  causes, one span:

  1. NestScanSpans took the FIRST `begin` after the header as the routine's own
     body -- at depth 2 that `begin` belongs to the INNER routine, so the lifter
     cut the enclosing routine in half at the inner one's `end;`.
  2. The free-variable scan skipped inner routines wholesale, so nothing ever
     threaded a depth-0 variable through the middle routine for the inner one to
     reach. The scan is transitive now: an inner routine's free variables are
     the enclosing routine's captures too, which is also what makes depth 3+
     work by construction.

  Every expected value below is FPC's own output for the same source. }

procedure Depth0Local;                { row 3 of the ticket's table }
var la: Integer;
  procedure B;
    procedure C;
    begin la := la + 1; end;
  begin C; end;
begin la := 0; B; writeln('d0local=', la); end;

procedure Depth0Param(pa: Integer);   { row 4 }
  procedure B;
    procedure C;
    begin writeln('d0param=', pa); end;
  begin C; end;
begin B; end;

procedure Depth1Local;                { row 5 }
  procedure B;
  var lb: Integer;
    procedure C;
    begin lb := lb + 1; end;
  begin lb := 5; C; writeln('d1local=', lb); end;
begin B; end;

procedure Depth1Param;                { row 6 }
  procedure B(k: Integer);
    procedure C;
    begin writeln('d1param=', k); end;
  begin C; end;
begin B(7); end;

procedure CapturesNothing;            { row 2 -- must-not-regress control }
  procedure B;
    procedure C;
    begin writeln('nocap'); end;
  begin C; end;
begin B; end;

{ Depth 3, capturing a local AND a param from every enclosing level at once:
  each level has to thread through what the levels below it need. }
procedure Deep(pa: Integer);
var la: Integer;
  procedure B(kb: Integer);
  var lb: Integer;
    procedure C(kc: Integer);
    var lc: Integer;
      function D(kd: Integer): Integer;
      begin
        lc := lc + kd;
        D := pa + la + kb + lb + kc + lc;
      end;
    begin lc := 100; writeln('D=', D(1)); writeln('lc=', lc); end;
  begin lb := 20; C(30); writeln('lb=', lb); end;
begin la := 10; B(2); writeln('la=', la); end;

{ The capture is BY REFERENCE two levels down: the writes must land in A's frame. }
procedure WritesThrough;
var acc: Integer;
  procedure B;
    procedure C;
    begin acc := acc * 2; end;
  begin C; C; C; end;
begin acc := 1; B; writeln('acc=', acc); end;

{ An inner routine's own local shadows the enclosing one of the same name --
  it must NOT become a capture, and the outer variable must survive untouched. }
procedure Shadowed;
var x: Integer;
  procedure B;
    procedure C;
    var x: Integer;
    begin x := 99; writeln('innerx=', x); end;
  begin C; writeln('bx=', x); end;
begin x := 7; B; writeln('afterx=', x); end;

{ A depth-2 sibling call, and a depth-2 self-recursive call, both of which have
  to carry the hidden captured-frame argument. }
procedure Siblings;
var la: Integer;
  procedure B;
    procedure C;
    begin la := la + 1; end;
    procedure E;
    begin C; C; end;
  begin E; end;
begin la := 0; B; writeln('sib=', la); end;

procedure Recurse;
var la: Integer;
  procedure B;
    function C(n: Integer): Integer;
    begin
      la := la + n;
      if n > 1 then C := C(n - 1) + n else C := n;
    end;
  begin writeln('rec=', C(4)); end;
begin la := 0; B; writeln('recla=', la); end;

{ Self capture through two levels: C touches the method's field, so `Self` has
  to be threaded down as well as the captured local. }
type
  TFoo = class
    V: Integer;
    procedure Run;
  end;

procedure TFoo.Run;
var la: Integer;
  procedure B;
    procedure C;
    begin V := V + la; end;
  begin C; end;
begin la := 5; V := 1; B; writeln('self=', V); end;

var f: TFoo;
begin
  Depth0Local;
  Depth0Param(9);
  Depth1Local;
  Depth1Param;
  CapturesNothing;
  Deep(1);
  WritesThrough;
  Shadowed;
  Siblings;
  Recurse;
  f := TFoo.Create;
  f.Run;
end.
