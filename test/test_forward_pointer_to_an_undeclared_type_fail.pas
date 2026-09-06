{ THE POSITIVE CONTROL for the forward-pointer drain: a `^T` whose T no section
  of the program ever declares must be refused.

  Until 2026-09-06 this compiled clean. The PtrElemDepth escape hatch in
  ParseTypeKindInner tolerates an unknown pointee name -- it has to, because
  `PNode = ^TNode;` above TNode is how every linked node in Pascal is spelled --
  and nothing ever came back to ask whether the name turned up. So the program
  below built, ran, and `SizeOf(p^)` answered 4, which is TypeStorageSize
  (tyUnknown) and not a size at all: the blank wearing the value of sizeof
  (Integer), which is exactly why nobody caught it by looking at the number.

  fpc 3.2.2: `Forward type not resolved "TNeverDeclared"`.

  The SizeOf line is deliberate and must stay: it is the only statement here
  that had an observable wrong answer, so if the refusal is ever narrowed away
  this file goes back to printing 4 rather than to a link error. }
program test_forward_pointer_to_an_undeclared_type_fail;
{$mode objfpc}

type
  PNever = ^TNeverDeclared;

var
  p: PNever;

begin
  p := nil;
  writeln(SizeOf(p^));
end.
