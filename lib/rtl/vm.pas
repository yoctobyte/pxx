unit vm;

{ A tiny stack-bytecode machine: ~21-opcode ISA, a text assembler (mnemonics +
  labels -> program), and an executor. Self-contained; not a language frontend.

  Representation avoids records-with-dynamic-array-fields (a known codegen bug):
  the program is two flat parallel Integer arrays (opcode + operand), and all
  working state (operand stack, call stack, memory) lives in a class with
  zero-initialised array fields, like the json/calc readers.

  ISA (operand column: imm = immediate, addr = memory cell, lbl = code address):
    push imm  pop  dup  swap
    add sub mul div mod neg
    lt gt eq            (pop b,a -> push ord(a OP b))
    load addr  store addr
    jmp lbl  jz lbl  jnz lbl     (jz/jnz pop the test value)
    call lbl  ret
    print     (pop, append decimal + newline to output)
    halt

  Assembler: one statement per line; `label:` may prefix a line or stand alone;
  `;` starts a comment. Run returns the accumulated PRINT output as a string, so
  oracles can compare it byte-for-byte. }

interface

type
  TIntArray = array of Integer;

  TMachine = class
    FOps:  TIntArray;          { opcode per instruction }
    FArgs: TIntArray;          { operand per instruction }
    FNum:  Integer;            { instruction count }

    FLabelName: array of AnsiString;
    FLabelAddr: TIntArray;
    FNLabels:   Integer;

    FOk:  Boolean;
    FErr: AnsiString;

    function Assemble(const src: AnsiString): Boolean;
    function Run: AnsiString;
    function Ok: Boolean;
    function Err: AnsiString;
  end;

implementation

uses sysutils;

const
  OP_PUSH  = 0;  OP_POP   = 1;  OP_DUP  = 2;  OP_SWAP = 3;
  OP_ADD   = 4;  OP_SUB   = 5;  OP_MUL  = 6;  OP_DIV  = 7;  OP_MOD = 8;
  OP_NEG   = 9;  OP_LT    = 10; OP_GT   = 11; OP_EQ   = 12;
  OP_LOAD  = 13; OP_STORE = 14;
  OP_JMP   = 15; OP_JZ    = 16; OP_JNZ  = 17;
  OP_CALL  = 18; OP_RET   = 19; OP_PRINT = 20; OP_HALT = 21;

  MEM_SIZE = 256;

{ opcode for a mnemonic, or -1 if unknown }
function OpcodeOf(const m: AnsiString): Integer;
begin
  if m = 'push' then Result := OP_PUSH
  else if m = 'pop' then Result := OP_POP
  else if m = 'dup' then Result := OP_DUP
  else if m = 'swap' then Result := OP_SWAP
  else if m = 'add' then Result := OP_ADD
  else if m = 'sub' then Result := OP_SUB
  else if m = 'mul' then Result := OP_MUL
  else if m = 'div' then Result := OP_DIV
  else if m = 'mod' then Result := OP_MOD
  else if m = 'neg' then Result := OP_NEG
  else if m = 'lt' then Result := OP_LT
  else if m = 'gt' then Result := OP_GT
  else if m = 'eq' then Result := OP_EQ
  else if m = 'load' then Result := OP_LOAD
  else if m = 'store' then Result := OP_STORE
  else if m = 'jmp' then Result := OP_JMP
  else if m = 'jz' then Result := OP_JZ
  else if m = 'jnz' then Result := OP_JNZ
  else if m = 'call' then Result := OP_CALL
  else if m = 'ret' then Result := OP_RET
  else if m = 'print' then Result := OP_PRINT
  else if m = 'halt' then Result := OP_HALT
  else Result := -1;
end;

{ does opcode read an operand from the instruction stream? }
function NeedsOperand(op: Integer): Boolean;
begin
  Result := (op = OP_PUSH) or (op = OP_LOAD) or (op = OP_STORE)
         or (op = OP_JMP) or (op = OP_JZ) or (op = OP_JNZ) or (op = OP_CALL);
end;

{ does opcode's operand name a code label (vs an immediate / address)? }
function OperandIsLabel(op: Integer): Boolean;
begin
  Result := (op = OP_JMP) or (op = OP_JZ) or (op = OP_JNZ) or (op = OP_CALL);
end;

{ Split one source line into up to three tokens: an optional `label:` prefix,
  a mnemonic, and an operand. Absent parts come back empty. Comments (`;`) and
  surrounding whitespace are stripped. }
procedure SplitLine(const lineIn: AnsiString; var lbl, mnem, operand: AnsiString);
var
  i, n: Integer;
  c: Char;
  toks: array of AnsiString;
  ntok, start: Integer;
  cut: Integer;
begin
  lbl := '';
  mnem := '';
  operand := '';

  { drop comment }
  cut := 0;
  for i := 1 to Length(lineIn) do
    if lineIn[i] = ';' then begin cut := i; Break; end;
  if cut > 0 then n := cut - 1 else n := Length(lineIn);

  { tokenize by whitespace }
  ntok := 0;
  i := 1;
  while i <= n do
  begin
    c := lineIn[i];
    if (c = ' ') or (c = #9) or (c = #13) then begin i := i + 1; Continue; end;
    start := i;
    while (i <= n) do
    begin
      c := lineIn[i];
      if (c = ' ') or (c = #9) or (c = #13) then Break;
      i := i + 1;
    end;
    SetLength(toks, ntok + 1);
    toks[ntok] := Copy(lineIn, start, i - start);
    ntok := ntok + 1;
  end;

  if ntok = 0 then Exit;

  start := 0;
  { a token ending in ':' is a label (the colon may be its own token too) }
  if toks[0][Length(toks[0])] = ':' then
  begin
    lbl := Copy(toks[0], 1, Length(toks[0]) - 1);
    start := 1;
  end;

  if start < ntok then begin mnem := toks[start]; start := start + 1; end;
  if start < ntok then operand := toks[start];
end;

{ ---- TMachine ---- }

function TMachine.Ok: Boolean;
begin
  Result := Self.FOk;
end;

function TMachine.Err: AnsiString;
begin
  Result := Self.FErr;
end;

function TMachine.Assemble(const src: AnsiString): Boolean;
var
  i, n, lineStart, insCount, op, k, val, sign: Integer;
  line, lbl, mnem, operand: AnsiString;
  c: Char;
  pass: Integer;
  found: Boolean;
begin
  Self.FOk := True;
  Self.FErr := '';
  Self.FNum := 0;
  Self.FNLabels := 0;
  SetLength(Self.FOps, 0);
  SetLength(Self.FArgs, 0);
  SetLength(Self.FLabelName, 0);
  SetLength(Self.FLabelAddr, 0);

  n := Length(src);

  { two passes over the source: pass 1 assigns label addresses, pass 2 emits }
  for pass := 1 to 2 do
  begin
    insCount := 0;
    i := 1;
    lineStart := 1;
    while i <= n + 1 do
    begin
      if (i > n) or (src[i] = #10) then
      begin
        line := Copy(src, lineStart, i - lineStart);
        SplitLine(line, lbl, mnem, operand);

        if (pass = 1) and (lbl <> '') then
        begin
          SetLength(Self.FLabelName, Self.FNLabels + 1);
          SetLength(Self.FLabelAddr, Self.FNLabels + 1);
          Self.FLabelName[Self.FNLabels] := lbl;
          Self.FLabelAddr[Self.FNLabels] := insCount;
          Self.FNLabels := Self.FNLabels + 1;
        end;

        if mnem <> '' then
        begin
          if pass = 2 then
          begin
            op := OpcodeOf(mnem);
            if op < 0 then
            begin
              Self.FOk := False;
              Self.FErr := 'unknown mnemonic: ' + mnem;
              Result := False;
              Exit;
            end;
            val := 0;
            if NeedsOperand(op) then
            begin
              if operand = '' then
              begin
                Self.FOk := False; Self.FErr := 'missing operand: ' + mnem;
                Result := False; Exit;
              end;
              if OperandIsLabel(op) then
              begin
                found := False;
                for k := 0 to Self.FNLabels - 1 do
                  if Self.FLabelName[k] = operand then
                  begin val := Self.FLabelAddr[k]; found := True; Break; end;
                if not found then
                begin
                  Self.FOk := False; Self.FErr := 'undefined label: ' + operand;
                  Result := False; Exit;
                end;
              end
              else
              begin
                { signed integer immediate }
                sign := 1; k := 1;
                if (Length(operand) >= 1) and (operand[1] = '-') then begin sign := -1; k := 2; end;
                val := 0;
                while k <= Length(operand) do
                begin
                  c := operand[k];
                  if (c >= '0') and (c <= '9') then val := val * 10 + (Ord(c) - Ord('0'))
                  else begin Self.FOk := False; Self.FErr := 'bad operand: ' + operand; Result := False; Exit; end;
                  k := k + 1;
                end;
                val := val * sign;
              end;
            end;
            SetLength(Self.FOps, insCount + 1);
            SetLength(Self.FArgs, insCount + 1);
            Self.FOps[insCount] := op;
            Self.FArgs[insCount] := val;
          end;
          insCount := insCount + 1;
        end;

        lineStart := i + 1;
      end;
      i := i + 1;
    end;
    if pass = 2 then Self.FNum := insCount;
  end;

  Result := Self.FOk;
end;

function TMachine.Run: AnsiString;
var
  stack, ret, mem: TIntArray;
  sp, rp, pc, op, arg, a, b: Integer;
  outp: AnsiString;
  steps: Integer;
begin
  SetLength(stack, 1024);
  SetLength(ret, 1024);
  SetLength(mem, MEM_SIZE);
  sp := 0; rp := 0; pc := 0;
  outp := '';
  steps := 0;

  while (pc >= 0) and (pc < Self.FNum) do
  begin
    steps := steps + 1;
    if steps > 100000000 then begin Self.FErr := 'step limit'; Self.FOk := False; Break; end;

    op := Self.FOps[pc];
    arg := Self.FArgs[pc];
    pc := pc + 1;

    if op = OP_PUSH then begin stack[sp] := arg; sp := sp + 1; end
    else if op = OP_POP then sp := sp - 1
    else if op = OP_DUP then begin stack[sp] := stack[sp - 1]; sp := sp + 1; end
    else if op = OP_SWAP then begin a := stack[sp - 1]; stack[sp - 1] := stack[sp - 2]; stack[sp - 2] := a; end
    else if op = OP_ADD then begin stack[sp - 2] := stack[sp - 2] + stack[sp - 1]; sp := sp - 1; end
    else if op = OP_SUB then begin stack[sp - 2] := stack[sp - 2] - stack[sp - 1]; sp := sp - 1; end
    else if op = OP_MUL then begin stack[sp - 2] := stack[sp - 2] * stack[sp - 1]; sp := sp - 1; end
    else if op = OP_DIV then
    begin
      if stack[sp - 1] = 0 then begin Self.FErr := 'div by zero'; Self.FOk := False; Break; end;
      stack[sp - 2] := stack[sp - 2] div stack[sp - 1]; sp := sp - 1;
    end
    else if op = OP_MOD then
    begin
      if stack[sp - 1] = 0 then begin Self.FErr := 'mod by zero'; Self.FOk := False; Break; end;
      stack[sp - 2] := stack[sp - 2] mod stack[sp - 1]; sp := sp - 1;
    end
    else if op = OP_NEG then stack[sp - 1] := -stack[sp - 1]
    else if op = OP_LT then begin if stack[sp - 2] < stack[sp - 1] then a := 1 else a := 0; stack[sp - 2] := a; sp := sp - 1; end
    else if op = OP_GT then begin if stack[sp - 2] > stack[sp - 1] then a := 1 else a := 0; stack[sp - 2] := a; sp := sp - 1; end
    else if op = OP_EQ then begin if stack[sp - 2] = stack[sp - 1] then a := 1 else a := 0; stack[sp - 2] := a; sp := sp - 1; end
    else if op = OP_LOAD then begin stack[sp] := mem[arg]; sp := sp + 1; end
    else if op = OP_STORE then begin sp := sp - 1; mem[arg] := stack[sp]; end
    else if op = OP_JMP then pc := arg
    else if op = OP_JZ then begin sp := sp - 1; if stack[sp] = 0 then pc := arg; end
    else if op = OP_JNZ then begin sp := sp - 1; if stack[sp] <> 0 then pc := arg; end
    else if op = OP_CALL then begin ret[rp] := pc; rp := rp + 1; pc := arg; end
    else if op = OP_RET then begin rp := rp - 1; pc := ret[rp]; end
    else if op = OP_PRINT then begin sp := sp - 1; outp := outp + IntToStr(stack[sp]) + #10; end
    else if op = OP_HALT then Break
    else begin Self.FErr := 'bad opcode'; Self.FOk := False; Break; end;
  end;

  Result := outp;
end;

end.
