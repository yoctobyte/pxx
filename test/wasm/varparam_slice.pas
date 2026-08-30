program VarParamSlice;
{ Forwarding a `var` parameter onward as ANOTHER routine's `var` argument.

  The shape is unremarkable in Pascal and it is everywhere in the compiler's own
  unit resolver, which is where it was found: ParseUsesUnitBody holds a local
  `path`, hands it to PyTryHostHeader as `var path`, and PyTryHostHeader hands
  that on again to ConcatThree as `var dst`. Two hops, and the second one is
  where wasm32 lowered a READ.

  Why it needs its own slice rather than a line in check_managed. IR_LEA on a
  scalar managed string is POSITION-DEPENDENT — read position yields the
  handle, write position yields the slot's address — and the lowering emits the
  SAME node for all four uses of a `var s: AnsiString` parameter. So the four
  uses below are not four variations on one theme; they are the four consumers
  of one node, and the only thing that separates them is which position the
  consumer asks for. A slice that exercised three of them would have passed
  before the fix.

  Both failure directions are here on purpose:

    * Fwd   — the callee RESIZES through the reference. Getting this wrong hands
              PXXStrSetLen the string's DATA pointer as a slot address, it reads
              a length from four characters of text, and the module TRAPS. Loud.
    * Pub   — the callee PUBLISHES a new handle through the reference. Getting
              this wrong stores a valid handle into the caller's character
              BYTES. Nothing traps, nothing validates differently, and the
              caller reads back a plausible wrong string. Silent, and the reason
              a diff against native is the primary assertion here.

  Read/Len/Idx/IdxW are the twins that must NOT move: they are reads (or a
  write reached through IR_INDEX, which owns its own position) and they were
  correct all along. A fix that made every argument a write position would
  break them, which is what they are for. }

procedure Resize(var d: AnsiString);
begin
  SetLength(d, 3);
  d[1] := 'x'; d[2] := 'y'; d[3] := 'z';
end;

procedure Publish(var d: AnsiString);
begin
  d := 'published';
end;

procedure ByValue(const c: AnsiString);
begin
  Writeln('byval=', c);
end;

{ THE shape: a `var` parameter forwarded into another `var` parameter. }
procedure Fwd(var p: AnsiString);
begin
  Resize(p);
end;

procedure Pub(var p: AnsiString);
begin
  Publish(p);
end;

{ The read twins, all reached through the same IR_LEA node as the two above. }
procedure Deref(var p: AnsiString);
begin
  ByValue(p);
end;

procedure Len(var p: AnsiString);
begin
  Writeln('len=', Length(p));
end;

procedure Idx(var p: AnsiString);
begin
  Writeln('idx=', p[1], p[2]);
end;

procedure IdxW(var p: AnsiString);
begin
  p[1] := 'Q';
end;

{ Three hops, because two is the depth the resolver actually used and a chain
  that only ever forwards once cannot tell "the callee's slot" from "the
  caller's slot" — they coincide at depth one. }
procedure Hop2(var p: AnsiString);
begin
  Resize(p);
end;

procedure Hop1(var p: AnsiString);
begin
  Hop2(p);
end;

{ The same forward through a VIRTUAL call, which reaches its arguments through
  a different emitter (WasmEmitIndArgs) than a direct call does. Fixing one and
  not the other is the failure that is hardest to attribute, because the direct
  case works and the method case does not. }
type
  TBase = class
    procedure Fill(var d: AnsiString); virtual;
  end;
  TDerived = class(TBase)
    procedure Fill(var d: AnsiString); override;
  end;

procedure TBase.Fill(var d: AnsiString);
begin
  d := 'base';
end;

procedure TDerived.Fill(var d: AnsiString);
begin
  Resize(d);
end;

var
  s: AnsiString;
  o: TBase;
  i: Integer;

begin
  s := 'abcdefgh'; Deref(s);
  s := 'abcdefgh'; Len(s);
  s := 'abcdefgh'; Idx(s);

  s := 'abcdefgh'; IdxW(s);  Writeln('idxw=', s);
  s := 'abcdefgh'; Fwd(s);   Writeln('fwd=', s);
  s := 'abcdefgh'; Pub(s);   Writeln('pub=', s);
  s := 'abcdefgh'; Hop1(s);  Writeln('hop=', s);

  { The virtual pair. TDerived forwards its `var` parameter on (the shape under
    test); TBase publishes into it directly (the shape that was already fine).
    Both go through the same VMT dispatch, so `virtbase=base` staying correct
    while `virt=xyz` is wrong is what separates "the argument emitter is broken"
    from "virtual dispatch is broken". }
  s := 'abcdefgh';
  o := TDerived.Create;
  o.Fill(s);
  Writeln('virt=', s);
  o.Free;

  o := TBase.Create;
  s := 'abcdefgh';
  o.Fill(s);
  Writeln('virtbase=', s);
  o.Free;

  { The reference must still be live after the callee resized it — a slot the
    callee wrote into by accident would leave the caller's name holding the OLD
    handle, which reads correctly right up until it is released twice. }
  s := 'abcdefgh';
  Fwd(s);
  for i := 1 to Length(s) do Write(s[i]);
  Writeln;
  Writeln('final-len=', Length(s));
end.
