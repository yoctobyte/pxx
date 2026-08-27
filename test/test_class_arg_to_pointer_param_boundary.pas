{ The legitimate half of `tyPointer <- tyClass` (symtab.inc), pinned so that
  tightening the illegitimate half cannot take it with it.

  A class instance MUST still bind an untyped `Pointer` parameter and a
  `TObject` parameter -- the builtin TObject param type is itself a tyPointer
  whose ELEMENT is a class, which is why the blanket rule exists at all. What
  must NOT be accepted is a pointer to an unrelated RECORD
  (bug-p-a-class-instance-converts-implicitly-to-any-typed-pointer); that half
  cannot be asserted from inside a Pascal program, since it is a compile-time
  diagnostic, so this file pins the half with the regression risk -- the same
  split as test/cerror_directive.c.

  Every routine here takes a class instance through a pointer-shaped parameter
  and must keep compiling and returning the right answer. }
program test_class_arg_to_pointer_param_boundary;
type
  TBase = class
  public
    N: Int64;
    constructor Create(AN: Int64);
  end;
  TSub = class(TBase)
  end;
  PBase = ^TBase;

constructor TBase.Create(AN: Int64);
begin
  N := AN;
end;

{ untyped Pointer: the everyday marshalling convention }
function ViaPointer(p: Pointer): Int64;
begin
  if p = nil then ViaPointer := -1 else ViaPointer := TBase(p).N;
end;

{ TObject formal: a tyPointer whose element IS a class -- must accept any class }
function ViaTObject(o: TObject): Int64;
begin
  if o = nil then ViaTObject := -1 else ViaTObject := TBase(o).N;
end;

{ a pointer to a CLASS type, as opposed to a pointer to a record }
function ViaPClass(p: PBase): Int64;
begin
  if p = nil then ViaPClass := -1 else ViaPClass := -2;
end;

var
  b: TBase;
  s: TSub;
  pb: PBase;
begin
  b := TBase.Create(11);
  s := TSub.Create(22);

  WriteLn(ViaPointer(b));
  WriteLn(ViaPointer(s));
  WriteLn(ViaTObject(b));
  WriteLn(ViaTObject(s));
  { nil must still reach both }
  WriteLn(ViaPointer(nil));
  WriteLn(ViaTObject(nil));
  { a genuine pointer-to-class argument, taken by address }
  pb := @b;
  WriteLn(ViaPClass(pb));
  WriteLn(ViaPClass(nil));
end.
