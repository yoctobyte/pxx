unit asmcore_base;
{$mode objfpc}{$H+}
{ Shared types for lib/asmcore: operands, instructions, patch sites, a
  growable byte buffer. Mechanical only — no labels, no symbol table, no
  dependency on compiler/**. See devdocs/developer/asmcore-design.md.
  {$mode objfpc}{$H+} is inert for PXX self-host (which already allows
  Result + ansistrings unconditionally) and is needed only so the FPC cold
  bootstrap (make bootstrap / make test-fpc) can compile this unit — FPC
  defaults to {$mode fpc}, where the Result pseudo-variable is off
  (bug-asmcore-fpc-bootstrap). }

interface

type
  TAsmOperandKind = (opReg, opImm, opMem, opPatch);

  TAsmOperand = record
    Kind: TAsmOperandKind;
    Reg: Integer;          { register number, target-defined constant }
    RegSize: Integer;      { width in bytes, where it matters (x64) }
    Imm: Int64;
    MemBase: Integer;      { -1 = none }
    MemIndex: Integer;     { -1 = none }
    MemScale: Integer;     { 1/2/4/8 }
    MemDisp: Int64;
    PatchWidth: Integer;   { 0 = not a patch site; else 1/2/4/8 }
  end;

  TAsmInstr = record
    Mnemonic: AnsiString;
    Operands: array[0..3] of TAsmOperand;
    OperandCount: Integer;
  end;

  TAsmPatchSite = record
    Offset: Integer;        { byte offset into the output buffer }
    Width: Integer;         { 1/2/4/8 }
    OperandIndex: Integer;  { which operand produced this, caller bookkeeping }
  end;

  TAsmByteBuf = record
    Bytes: array of Byte;
    Len: Integer;
  end;

  TAsmPatchList = record
    Items: array of TAsmPatchSite;
    Count: Integer;
  end;

function RegOp(reg, size: Integer): TAsmOperand;
function ImmOp(v: Int64): TAsmOperand;
function MemOp(base: Integer; disp: Int64): TAsmOperand;
function MemOpIndexed(base, index, scale: Integer; disp: Int64): TAsmOperand;
function PatchOp(width: Integer): TAsmOperand;

procedure BufInit(var buf: TAsmByteBuf);
procedure BufAppend(var buf: TAsmByteBuf; b: Byte);
procedure BufAppendI32(var buf: TAsmByteBuf; v: Int64);
procedure BufAppendI64(var buf: TAsmByteBuf; v: Int64);

procedure PatchListInit(var list: TAsmPatchList);
procedure PatchAdd(var list: TAsmPatchList; offset, width, operandIndex: Integer);

implementation

function RegOp(reg, size: Integer): TAsmOperand;
begin
  Result.Kind := opReg;
  Result.Reg := reg;
  Result.RegSize := size;
  Result.Imm := 0;
  Result.MemBase := -1; Result.MemIndex := -1; Result.MemScale := 1; Result.MemDisp := 0;
  Result.PatchWidth := 0;
end;

function ImmOp(v: Int64): TAsmOperand;
begin
  Result.Kind := opImm;
  Result.Reg := -1; Result.RegSize := 0;
  Result.Imm := v;
  Result.MemBase := -1; Result.MemIndex := -1; Result.MemScale := 1; Result.MemDisp := 0;
  Result.PatchWidth := 0;
end;

function MemOp(base: Integer; disp: Int64): TAsmOperand;
begin
  Result.Kind := opMem;
  Result.Reg := -1; Result.RegSize := 0;
  Result.Imm := 0;
  Result.MemBase := base; Result.MemIndex := -1; Result.MemScale := 1; Result.MemDisp := disp;
  Result.PatchWidth := 0;
end;

{ [base + index*scale + disp] — SIB addressing. base = -1 means "no base
  register" (index*scale+disp only); index = -1 degrades to plain MemOp.
  scale must be 1/2/4/8 (target encoders reject anything else). }
function MemOpIndexed(base, index, scale: Integer; disp: Int64): TAsmOperand;
begin
  Result.Kind := opMem;
  Result.Reg := -1; Result.RegSize := 0;
  Result.Imm := 0;
  Result.MemBase := base; Result.MemIndex := index; Result.MemScale := scale; Result.MemDisp := disp;
  Result.PatchWidth := 0;
end;

function PatchOp(width: Integer): TAsmOperand;
begin
  Result.Kind := opPatch;
  Result.Reg := -1; Result.RegSize := 0;
  Result.Imm := 0;
  Result.MemBase := -1; Result.MemIndex := -1; Result.MemScale := 1; Result.MemDisp := 0;
  Result.PatchWidth := width;
end;

procedure BufGrow(var buf: TAsmByteBuf; need: Integer);
var newCap: Integer;
begin
  if buf.Len + need <= Length(buf.Bytes) then Exit;
  newCap := Length(buf.Bytes) * 2;
  if newCap < buf.Len + need then newCap := buf.Len + need;
  if newCap < 64 then newCap := 64;
  SetLength(buf.Bytes, newCap);
end;

procedure BufInit(var buf: TAsmByteBuf);
begin
  SetLength(buf.Bytes, 0);
  buf.Len := 0;
end;

procedure BufAppend(var buf: TAsmByteBuf; b: Byte);
begin
  BufGrow(buf, 1);
  buf.Bytes[buf.Len] := b;
  Inc(buf.Len);
end;

procedure BufAppendI32(var buf: TAsmByteBuf; v: Int64);
begin
  BufAppend(buf, Byte(v and $FF));
  BufAppend(buf, Byte((v shr 8) and $FF));
  BufAppend(buf, Byte((v shr 16) and $FF));
  BufAppend(buf, Byte((v shr 24) and $FF));
end;

procedure BufAppendI64(var buf: TAsmByteBuf; v: Int64);
begin
  BufAppendI32(buf, v and $FFFFFFFF);
  BufAppendI32(buf, (v shr 32) and $FFFFFFFF);
end;

procedure PatchListInit(var list: TAsmPatchList);
begin
  SetLength(list.Items, 0);
  list.Count := 0;
end;

procedure PatchAdd(var list: TAsmPatchList; offset, width, operandIndex: Integer);
begin
  if list.Count >= Length(list.Items) then
    SetLength(list.Items, list.Count * 2 + 4);
  list.Items[list.Count].Offset := offset;
  list.Items[list.Count].Width := width;
  list.Items[list.Count].OperandIndex := operandIndex;
  Inc(list.Count);
end;

end.
