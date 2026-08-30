{ A METACLASS VARIABLE as the receiver of a parenless method reference --
  `mc: class of TSvc; f := TSel(mc.Virt)` -- and the VMT lookup that has to
  follow it.

  TWO DEFECTS, ONE PROGRAM, and the second is why this test exists in this shape.

  (1) THE RECEIVER WAS NOT RECOGNISED. `TryParseParenlessMethodRef` knew an
  instance VARIABLE (a symbol whose RecName is a class) and a class NAME. A
  metaclass variable is neither: it is a tyPointer whose POINTEE is a class, so
  it missed both arms and fell through to the call path --
  `"TSvc.Plain" is a procedure and has no result to use in an expression`. It is
  now asked through SymMetaclassCi, which is NodeMetaclassCi's AN_IDENT arm split
  to symbol level so this site can decide before it has allocated any node.

  (2) THE VMT WAS THEN READ FROM THE WRONG PLACE, and this half compiled clean
  and SIGSEGV'd. A class method's Self is the class RTTI BLOB, whose VMT sits at
  +24 -- a blob's +0 is its NAME pointer. `IRMethodRefCode` decided that by
  asking whether the receiver node was spelled AN_CLASSREF. A metaclass VARIABLE
  carries the identical blob in an AN_IDENT, so it took the instance path and
  indexed off the name pointer. Measured, on the binary that had (1) fixed and
  not (2): `svc.plain` printed (a NON-virtual class method needs no VMT at all
  and takes the IR_PROCADDR short-circuit) and the very next line, the first
  VIRTUAL one, segfaulted.

  THAT IS WHY THE VIRTUAL ROWS ARE THE POINT. A test with only `Plain` in it
  passes on a compiler with defect (2) still in place -- it never reads a VMT --
  and would have blessed a wrong code pointer. Three of the five rows below are
  virtual for that reason, and the last dispatches through a DERIVED metaclass so
  a reference taken through a base-typed variable is proved to capture the
  override rather than merely to be non-nil.

  Pre-fix behaviour, both stages, so the rows can be read as measurements:

    pinned                     compile error on the first `TSel(mc.Plain)`
    (1) fixed, (2) not         `svc.plain` then SIGSEGV on `TSel(mc.Virt)`
    both fixed                 matches FPC line for line

  Oracle: FPC 3.2.2 prints the same five lines.
  bug-p-a-parenless-method-reference-handles-two-of-four-receiver-spellings }
program test_method_ref_through_a_metaclass_variable;

{$MODE DELPHI}

type
  TSel = procedure of object;

  TSvc = class
    class procedure Plain;
    class procedure Virt; virtual;
  end;

  TDeriv = class(TSvc)
    class procedure Virt; override;
  end;

  TSvcClass = class of TSvc;

class procedure TSvc.Plain;  begin writeln('svc.plain');  end;
class procedure TSvc.Virt;   begin writeln('svc.virt');   end;
class procedure TDeriv.Virt; begin writeln('deriv.virt'); end;

var
  mc: TSvcClass;
  f: TSel;
begin
  mc := TSvc;

  { non-virtual: IR_PROCADDR, no VMT read -- the row that passes even with the
    VMT defect in place, kept as the control that isolates it }
  f := TSel(mc.Plain); f();

  { virtual, cast context }
  f := TSel(mc.Virt);  f();

  { virtual, assignment context -- the other half of the same decision }
  f := mc.Virt;        f();

  { and through a DERIVED metaclass: the reference must capture the override }
  mc := TDeriv;
  f := TSel(mc.Virt);  f();

  writeln('done');
end.
