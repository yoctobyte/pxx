{ `var Names: array[...] of T = (...)` INSIDE A ROUTINE was refused with

    error: local var-section ARRAY initializer not supported; assign in statements

  — a message that reads like a missing capability and was a missing FORK. The
  capability was present TWICE over: the same declaration at FILE SCOPE has
  always worked, and so has the local `const` spelling. ParseVarSection's array
  loop already reads its dimensions off the SYMBOL rather than from the parse;
  it just wrote `PendingInit*` at all seven of its element sites, and a routine
  has no pending-init table. `RegisterVarInitElem` makes that choice once.

  fcl-passrc's pparser.pp:635 is the live case — `CCNames: Array[TCallingConvention]
  of String = ('', 'register', ...)` inside `IsCallingConvention`.

  THE TWO CONTROLS ARE THE SPELLINGS THAT ALREADY WORKED, and they are here
  because this fix threads a flag through code both of them run. `global` is the
  file-scope var; `localconst` is the local const. If either moved, the fork is
  wrong rather than merely incomplete — and neither can be observed from a file
  that only tests the new spelling.

  THE `reentry` ROW IS THE SEMANTIC ONE AND IT WAS MEASURED, NOT ASSUMED. An
  initialised local could plausibly be a static initialised once (FPC's `{$J+}`
  typed-const behaviour) or an assignment on entry, every call. fpc 3.2.2
  `-Mobjfpc` prints 11 11 11 for a mutated-and-recalled initialised local, array
  and scalar alike — it re-initialises — and so does pxx. The row asserts the
  agreement rather than leaving it to be discovered by someone whose program
  depends on it.

  A ROUTINE-LOCAL DYNAMIC ARRAY IS STILL REFUSED and that is deliberate, not an
  oversight: its element list is carried as an AST node (pending-init kind 10)
  and FlushLocalInits reads kinds 0/1/2/4/5/9, none of which holds a node. fpc
  accepts it. The refusal is narrowed to say which half is missing, and the
  remainder is filed rather than left inside a message about arrays in general.
  feature-p-a-local-var-section-array-initializer }
{$mode objfpc}
program test_a_routine_local_var_array_initializer;
uses SysUtils;
type
  TCC = (ccNone, ccReg, ccCdecl);
  TBase = class end;
  TDer  = class(TBase) end;
  TCls  = class of TBase;

{ CONTROL 1: the file-scope spelling, which already worked }
var GNames: array[TCC] of string = ('', 'register', 'cdecl');

{ THE WIDTH ROWS, GLOBAL AND LOCAL, and they exist because the first version of
  this fix shipped a regression THIS FILE COULD NOT SEE. The helper that routes
  an element to its table took `val: Integer` while both tables hold Int64, so
  every 64-bit element was truncated — on the GLOBAL path, which the change was
  only meant to pass through. Three test-core rows went red and none of them was
  local. Every element above is a string, a small integer or a class reference:
  all of them survive a narrowing to 32 bits intact, so the file was green.
  BOTH VALUES ARE CHOSEN SO TRUNCATION IS NOT SILENT. 35.75's IEEE low word is
  exactly zero, so a lost high word reads 0.00 rather than a near-miss; and
  6000000000 mod 2^32 = 1705032704, nowhere near it. A value whose high word is
  already zero would pass either way. }
var GDbl: array[0..1] of Double = (35.75, -1.5);
var GQwd: array[0..1] of Int64  = (6000000000, -6000000000);

function LocalStrings(c: TCC): string;
var Names: array[TCC] of string = ('', 'register', 'cdecl');
begin
  LocalStrings := Names[c];
end;

function LocalInts: Integer;
var N: array[0..2] of Integer = (7, 8, 9);
begin
  LocalInts := N[0] * 100 + N[1] * 10 + N[2];
end;

function LocalGrid: Integer;
var M: array[0..1, 0..2] of Integer = ((1, 2, 3), (4, 5, 6));
begin
  LocalGrid := M[0, 0] + M[0, 2] + M[1, 0] + M[1, 2];
end;

function LocalChars: string;
var C: array[1..4] of Char = 'ABCD';
begin
  LocalChars := C[1] + C[4];
end;

function LocalClasses: string;
var K: array[0..1] of TCls = (TBase, TDer);
begin
  LocalClasses := K[0].ClassName + '/' + K[1].ClassName;
end;

function LocalDbl: string;
var D: array[0..1] of Double = (35.75, -1.5);
    t: string;
begin
  t := FloatToStrF(D[0], ffFixed, 15, 2);
  LocalDbl := t + ' ' + FloatToStrF(D[1], ffFixed, 15, 2);
end;

function LocalQwd: Int64;
var Q: array[0..1] of Int64 = (6000000000, -6000000000);
begin
  LocalQwd := Q[0] + Q[1] + Q[0];
end;

{ CONTROL 2: the local CONST spelling, which already worked }
function LocalConst(c: TCC): string;
const Names: array[TCC] of string = ('', 'register', 'cdecl');
begin
  LocalConst := Names[c];
end;

{ the entry semantics: mutate and re-enter }
function Reentry: Integer;
var A: array[0..1] of Integer = (10, 20);
begin
  A[0] := A[0] + 1;
  Reentry := A[0];
end;

begin
  WriteLn('local str  = ', LocalStrings(ccReg), '/', LocalStrings(ccCdecl));
  WriteLn('local int  = ', LocalInts);
  WriteLn('local grid = ', LocalGrid);
  WriteLn('local char = ', LocalChars);
  WriteLn('local cls  = ', LocalClasses);
  WriteLn('global     = ', GNames[ccReg], '/', GNames[ccCdecl]);
  WriteLn('localconst = ', LocalConst(ccReg), '/', LocalConst(ccCdecl));
  WriteLn('local dbl  = ', LocalDbl);
  WriteLn('local qwd  = ', LocalQwd);
  WriteLn('global dbl = ', FloatToStrF(GDbl[0], ffFixed, 15, 2), ' ', FloatToStrF(GDbl[1], ffFixed, 15, 2));
  WriteLn('global qwd = ', GQwd[0], ' ', GQwd[1]);
  WriteLn('reentry    = ', Reentry, ' ', Reentry, ' ', Reentry);
end.
