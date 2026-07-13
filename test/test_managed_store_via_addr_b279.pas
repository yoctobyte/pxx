{ Storing a string LITERAL through an ADDRESS: a class field, a record field, an array
  element, a pointer deref.

  IR_STORE_SYM (a plain variable) has handled managed strings since they landed;
  IR_STORE_MEM (everything reached through an address) did NOT, on riscv32 -- it wrote the
  raw source word into the slot.

  For a value that ALREADY is a handle -- a concat result, a function result, a copy of
  another string -- the raw word happens to be correct, which is exactly what hid this:
  `F := 'a' + n` and `s := 'lit'; F := s` both worked. A FROZEN LITERAL is not a handle, it
  is the address of inline data, so `F := 'lit'` stored a pointer to the literal into a
  managed slot and the field read back EMPTY. Silent: no crash, no diagnostic, just ''.

  Every form below is asserted with a literal AND with a value that is already a handle, so
  a backend that only implements the easy half cannot pass. }
program test_managed_store_via_addr_b279;

type
  TRec = record
    S: string;
  end;
  TA = class
    F: string;
    procedure SetLit;
    procedure SetCat(const n: string);
  end;

procedure TA.SetLit;
begin
  F := 'in-method-lit';
end;

procedure TA.SetCat(const n: string);
begin
  F := 'cat:' + n;
end;

var
  a: TA;
  r: TRec;
  arr: array[0..2] of string;
  s: string;
begin
  a := TA.Create;

  { class field }
  a.F := 'field-lit';                 writeln('field-lit=[', a.F, ']');
  a.SetLit;                           writeln('method-lit=[', a.F, ']');
  a.SetCat('x');                      writeln('method-cat=[', a.F, ']');
  s := 'via-var';
  a.F := s;                           writeln('field-var=[', a.F, ']');
  a.F := a.F + '!';                   writeln('field-self-cat=[', a.F, ']');

  { record field }
  r.S := 'rec-lit';                   writeln('rec-lit=[', r.S, ']');
  r.S := 'rec:' + s;                  writeln('rec-cat=[', r.S, ']');

  { array element }
  arr[0] := 'arr-lit';                writeln('arr-lit=[', arr[0], ']');
  arr[1] := 'arr:' + s;               writeln('arr-cat=[', arr[1], ']');
  arr[2] := arr[0];                   writeln('arr-copy=[', arr[2], ']');

  { NOT covered here: a raw `^string` deref (`p: PStr; p := @s; p^`). That is broken on
    x86-64 too, at the READ, and predates this -- see bug-pascal-deref-managed-string-ptr. }

  { a char, which also has to become a handle }
  a.F := 'z';                         writeln('char-lit=[', a.F, ']');
end.
