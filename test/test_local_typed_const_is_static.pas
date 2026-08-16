{ A routine-local typed const is STATIC in FPC: storage that outlives the call,
  initialised once. pxx gave it a stack slot and re-ran the initialiser from the
  prologue, so the counter idiom printed 1 forever and every mutation was undone
  on the next call (bug-p-a-routine-local-typed-const-is-reinitialised-on-every-
  call). Storage is now BSS and the initialiser runs behind a one-time guard,
  the same shape the C frontend uses for a block-scope `static`.
  A plain `var x: T = init` must still re-initialise on EVERY call -- that is
  its own correct semantics, and the last routine here is the control.
  Every value below is what `fpc -O- -Mobjfpc` prints. }
program test_local_typed_const_is_static;

procedure PInt;
const n: integer = 0;
begin Inc(n); write(n, ' '); end;

procedure PArr;
const arr: array[0..2] of integer = (1, 2, 3);
begin Inc(arr[0]); write(arr[0], ' '); end;

procedure PBool;
const b: boolean = false;
begin b := not b; write(b, ' '); end;

procedure PChar;
const c: char = 'a';
begin c := Succ(c); write(c, ' '); end;

procedure PTwo;
const a: integer = 10; b: integer = 20;
begin Inc(a); Inc(b, 2); write(a, '/', b, ' '); end;

procedure PVarControl;
var v: integer = 5;
begin Inc(v); write(v, ' '); end;

procedure PNested;
const outer: integer = 100;
  { the inner const is deliberately NOT named `inner`: a local const whose name
    matches its own NESTED routine binds the routine's mangled name instead --
    pre-existing and unrelated, filed as
    bug-p-a-const-named-like-its-nested-routine-binds-the-routine }
  procedure Inner;
  const icount: integer = 0;
  begin Inc(icount); write('i', icount, ' '); end;
begin Inc(outer); write('o', outer, ' '); Inner; Inner; end;

begin
  PInt; PInt; PInt; writeln;
  PArr; PArr; PArr; writeln;
  PBool; PBool; PBool; writeln;
  PChar; PChar; PChar; writeln;
  PTwo; PTwo; writeln;
  PVarControl; PVarControl; PVarControl; writeln;
  PNested; PNested; writeln;
end.
