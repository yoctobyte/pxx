{ The built-in POINTER type names — PInteger, PByte, PWord, PDouble, ... — in a TYPE position
  AND in a CAST: `var q: PInteger` and `PInteger(p)^`. Neither existed.

  The shadowing half of this is the part that matters, and it is asserted below.

  ParseTypeKind's builtin-name chain runs BEFORE the alias table is consulted (despite a comment
  in it claiming otherwise), so every name in that chain shadows a source declaration of the same
  name. For `widechar`/`tdatetime` that is latent — nobody redeclares them. For the P-names it is
  fatal: THIS COMPILER declares `PWord = ^NativeInt` (the machine word), and a builtin
  `PWord = ^UInt16` silently re-types it — `pw^` then reads TWO bytes instead of eight.

  So the builtin names are consulted only when FindTypeAlias MISSES, and the cast path registers
  them lazily on first use for the same reason. A program that declares its own PWord/PInteger
  must get its own, and that is what the first two lines below check.

  Note the self-host gate did NOT catch this — the compiler's own PWord kept working by luck of
  where it is declared. Only a test that redeclares the name shows it. }
program test_builtin_pointer_types_b303;

type
  PWord = ^NativeInt;      { shadows the builtin ^UInt16 — exactly what the compiler does }
  PInteger = ^Int64;       { shadows the builtin ^Int32 }

var
  n: NativeInt;
  i64: Int64;
  b: Byte;
  c: Cardinal;
  d: Double;
  pw: PWord;
  pi: PInteger;
  p: Pointer;
begin
  { a SOURCE declaration must beat the builtin, in a type position AND in a cast }
  n := $1122334455667788;
  pw := @n;
  writeln('source PWord is ^NativeInt : ', pw^ = n);
  p := @n;
  writeln('cast via source PWord      : ', PWord(p)^ = n);

  i64 := -5;
  pi := @i64;
  writeln('source PInteger is ^Int64  : ', pi^);

  { builtins the source did NOT redeclare }
  b := 200;   p := @b;   writeln('PByte      : ', PByte(p)^);
  c := 4000000000;  p := @c;  writeln('PCardinal  : ', PCardinal(p)^);
  d := 2.5;   p := @d;   writeln('PDouble    : ', PDouble(p)^:0:1);

  { and in a TYPE position, not just a cast }
  writeln('done');
end.
