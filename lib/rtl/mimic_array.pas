{ SPDX-License-Identifier: Zlib }
unit mimic_array;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `array` module — a flat, typed, fixed-width numeric buffer.

  `import array` RESOLVES here through the NilPy import resolver's `mimic_`
  fallback, so no file in the tree carries the stdlib's name and `--no-shims`
  can turn the substitution into an error. See devdocs/dev/python-compat-tiers.md.

  THE CLASS IS SPELLED `array_`, NOT `array`. CPython's module exports one
  public name and it is the module's own: `array.array`. `array` is a Pascal
  reserved word, so no unit can declare a class of that name; the trailing
  underscore is the convention the qualified-member mapper already applies
  (`tk.END` -> END_, PyMapReservedMember). A NilPy program writes
  `array.array("h")` and never sees this spelling. Until this shim was written
  that mapping reached the value and call paths but NOT the constructor path,
  where `array.array("h")` silently evaluated to 104 — ord('h') — and then
  segfaulted; fixed in the same commit.

  WHY THIS IS A PASCAL SHIM AND NOT A `.py` ONE. The resolver does not care
  which language a `mimic_` unit is written in — mimic_codecs, mimic_string and
  mimic_urllib_request are Pascal, mimic_bisect and mimic_copy are Python — so
  the choice is free and is decided by the work. This module's entire job is
  reinterpreting one byte buffer as int16/float32/…, which Pascal does with a
  pointer cast and which pure Python can only do by hand-rolling IEEE-754. A
  `.py` shim would also have needed `struct`, which does not exist here yet.

  THE SUBSET, stated plainly. Every typecode CPython has, because they are one
  parameterised size-and-signedness rule rather than twelve cases, and stopping
  at eleven would be an arbitrary line. What is NOT here: `array` is not
  iterable, sliceable, comparable or pickleable, and `fromfile`/`tofile`/
  `fromlist`/`tolist`/`extend`/`append`/`insert`/`pop`/`remove`/`reverse`/
  `index`/`count`/`buffer_info` are absent. The measured surface is
  construction (empty, from bytes, from a list), `frombytes`, `tobytes`,
  `byteswap`, `itemsize`, `typecode`, `len()`, and indexed read and write —
  which is what lekkerzeilen's world/audio/app reach and nothing beyond it. A
  caller who needs more gets a loud unknown-method error rather than a silently
  wrong buffer.

  ENDIANNESS. The buffer is always the HOST's byte order, exactly as CPython's
  is; `byteswap` reverses each element in place and is the only thing that
  changes it. That is what makes the `struct.pack("<h",1) != struct.pack("=h",1)`
  idiom real programs use behave the same way here. }

interface

uses pylib, sysutils;

type
  { Typed pointers for the reinterpretation. Declared locally rather than
    assumed from the RTL so this unit states its own requirements. }
  PA_I8  = ^ShortInt;   PA_U8  = ^Byte;
  PA_I16 = ^SmallInt;   PA_U16 = ^Word;
  PA_I32 = ^LongInt;    PA_U32 = ^LongWord;
  PA_I64 = ^Int64;      PA_U64 = ^QWord;
  PA_F32 = ^Single;     PA_F64 = ^Double;

  { `array.array(typecode[, initializer])`. }
  array_ = class
  public
    { CPython exposes both of these as read-only attributes and real programs
      READ them — world.py refuses a file whose `itemsize != 2` rather than
      decoding it wrong — so they are plain public fields. }
    typecode: AnsiString;
    itemsize: Integer;
    FLen: Integer;       { element COUNT, not byte count }
    FCap: Integer;       { BYTES allocated at FData }
    FData: Pointer;
    FIsFloat: Boolean;
    FSigned: Boolean;

    constructor Create(const tc: AnsiString); overload;
    { `array.array("h", bytes(n))` and `array.array("f", [1.0, 2.0])`.
      A BYTES initialiser is raw bytes — exactly `frombytes` — while a LIST
      initialiser is element VALUES. The same argument position means opposite
      things depending on its type; that asymmetry is CPython's, not ours.

      ONE constructor that dispatches on the runtime type, NOT two overloads,
      and that is a WORKAROUND rather than a design: NilPy resolves overloaded
      CONSTRUCTORS by first name match and ignores argument class identity, so
      the two-overload spelling silently ran the bytes body for a list argument
      and raised "bytes length not a multiple of item size" from a call that
      passed no bytes. Measured against the function spelling, which is
      correct — see the ticket. Same shape as pylib's own `bytes(b: TPyBytes)`
      runtime `is` check, which exists for the function-side version of this
      and is documented there.
      REVERT TO TWO OVERLOADS once that is fixed; the declaration below is the
      only thing holding the workaround.
      bug-n-an-overloaded-constructor-is-picked-by-name-ignoring-argument-type }
    constructor Create(const tc: AnsiString; init: TPyBytes); overload;
    destructor Destroy; override;

    { Not part of the Python surface — the storage primitives the methods below
      share. Public only because this dialect's classes have no private section
      (neither pylib nor any existing mimic_ unit uses one). }
    procedure SetTc(const tc: AnsiString);
    procedure SetCount(n: Integer);
    function ByteAt(i: Integer): NativeInt;

    procedure frombytes(b: TPyBytes);
    function tobytes: TPyBytes;
    procedure byteswap;
    { `len(a)`. A class that is not one of pylib's own containers is measured by
      `__len__` and by nothing else — without it the overload matcher silently
      picks the TPyList overload and reads a length off whatever bytes sit at
      that offset (bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-
      arithmetic). The name is the Python one because that is what the frontend
      looks up. }
    function __len__: Integer;

    function at(i: Integer): Variant;
    procedure put(i: Integer; const v: Variant);
    { `a[i]` read and write. Variant rather than two typed properties because
      one buffer answers in Int64 for ten typecodes and in Double for two, and
      which it is is a RUNTIME property of the instance. }
    property Items[i: Integer]: Variant read at write put; default;
  end;

{ EXPORTED so mimic_struct can read the same twelve rows rather than carry its
  own copy. See the implementation for why one table serves both modules: our
  fixed widths ARE struct's standard sizes. }
function PyTypecode(c: Char; var size: Integer; var isFloat: Boolean;
                    var signed: Boolean): Boolean;

implementation

function PyTypecode(c: Char; var size: Integer; var isFloat: Boolean;
                    var signed: Boolean): Boolean;
{ The typecode table, in ONE place, and it is now shared with mimic_struct.

  It was a `case` inside array_.SetTc until 2026-09-10, when the struct shim
  needed the same twelve rows. Copying them would have been the obvious move
  and would have put the DIVERGENCE NOTE below into two files that must agree
  and have no way to notice when they stop.

  CPython's sizes are the C ones, so `l`/`L` are 8 bytes on LP64 and 4 on
  Windows; ours are fixed at 4. That is deliberate — a program that writes a
  file with `l` and reads it back on another machine wants the width it wrote
  — and `itemsize` reports what we actually use, so the `itemsize != 2` guard
  real code writes still tells the truth about this buffer. It also happens to
  be exactly what `struct` means by a STANDARD size, which is why one table
  serves both: struct's standard `l` IS 4 bytes.

  Returns False for a code it does not know, leaving the outputs untouched, so
  each caller can raise the error ITS module's users expect — ValueError from
  array, struct.error from struct. }
begin
  PyTypecode := True;
  isFloat := False;
  signed := True;
  case c of
    'b': size := 1;
    'B': begin size := 1; signed := False; end;
    'u': begin size := 4; signed := False; end;   { Py_UCS4 — array only }
    'h': size := 2;
    'H': begin size := 2; signed := False; end;
    'i': size := 4;
    'I': begin size := 4; signed := False; end;
    'l': size := 4;
    'L': begin size := 4; signed := False; end;
    'q': size := 8;
    'Q': begin size := 8; signed := False; end;
    'f': begin size := 4; isFloat := True; end;
    'd': begin size := 8; isFloat := True; end;
  else
    PyTypecode := False;
  end;
end;

procedure array_.SetTc(const tc: AnsiString);
begin
  typecode := tc;
  itemsize := 0;
  FIsFloat := False;
  FSigned := True;
  FLen := 0;
  FCap := 0;
  FData := nil;
  if Length(tc) = 1 then
    if not PyTypecode(tc[1], itemsize, FIsFloat, FSigned) then itemsize := 0;
  { CPython raises ValueError here, and so must we: an unknown typecode that
    quietly produced a zero-width buffer would turn a typo into an empty array
    and every later read into a bounds error far from the cause. }
  if itemsize = 0 then
    raise Exception.Create('bad typecode (must be b, B, u, h, H, i, I, l, L, q, Q, f or d)');
end;

procedure array_.SetCount(n: Integer);
var need, k: Integer; p: PA_U8; nd: Pointer;
begin
  if n < 0 then n := 0;
  need := n * itemsize;
  if need > FCap then
  begin
    { Grow geometrically: audio.py fills a buffer one element at a time through
      the list constructor, and a realloc per element made that quadratic. }
    if FCap = 0 then FCap := need else
      while FCap < need do FCap := FCap * 2;
    GetMem(nd, FCap);
    if FData <> nil then
    begin
      Move(FData^, nd^, FLen * itemsize);
      FreeMem(FData);
    end;
    FData := nd;
  end;
  { New elements are ZERO, as CPython's are when a buffer is sized from bytes. }
  if n > FLen then
    for k := FLen * itemsize to n * itemsize - 1 do
    begin
      p := PA_U8(NativeInt(FData) + k);
      p^ := 0;
    end;
  FLen := n;
end;

function array_.ByteAt(i: Integer): NativeInt;
begin
  { One bounds check for every element access, rather than one per typecode
    arm. CPython raises IndexError; so do we, and the message names the index
    because an off-by-one in a decode loop is otherwise indistinguishable from
    a corrupt file. }
  if (i < 0) or (i >= FLen) then
    raise Exception.Create('array index out of range: ' + IntToStr(i));
  Result := NativeInt(FData) + i * itemsize;
end;

constructor array_.Create(const tc: AnsiString);
begin
  SetTc(tc);
end;

constructor array_.Create(const tc: AnsiString; init: TPyBytes);
var k: Integer; asList: TPyList;
begin
  SetTc(tc);
  if init = nil then Exit;
  { The declared parameter type is TPyBytes and a LIST arrives here too — see
    the declaration's comment for why this is one constructor and not two. }
  if TObject(init) is TPyList then
  begin
    asList := TPyList(TObject(init));
    SetCount(len(asList));
    for k := 0 to FLen - 1 do
      put(k, asList.at(k));
    Exit;
  end;
  frombytes(init);
end;

destructor array_.Destroy;
begin
  if FData <> nil then FreeMem(FData);
  FData := nil;
  inherited Destroy;
end;

function array_.__len__: Integer;
begin
  Result := FLen;
end;

procedure array_.frombytes(b: TPyBytes);
var addN, oldLen: Integer;
begin
  if b = nil then Exit;
  { CPython: "bytes length not a multiple of item size" is a ValueError. Silent
    truncation here would decode a whole terrain file off by a partial element. }
  if (b.FLen mod itemsize) <> 0 then
    raise Exception.Create('bytes length not a multiple of item size');
  addN := b.FLen div itemsize;
  if addN = 0 then Exit;
  oldLen := FLen;
  SetCount(oldLen + addN);
  Move(b.FData^, PA_U8(NativeInt(FData) + oldLen * itemsize)^, b.FLen);
end;

function array_.tobytes: TPyBytes;
begin
  Result := TPyBytes.Create(FLen * itemsize);
  if FLen > 0 then Move(FData^, Result.FData^, FLen * itemsize);
end;

procedure array_.byteswap;
var e, k, lo, hi: Integer; a, b: PA_U8; t: Byte; base: NativeInt;
begin
  if itemsize = 1 then Exit;
  for e := 0 to FLen - 1 do
  begin
    base := NativeInt(FData) + e * itemsize;
    lo := 0;
    hi := itemsize - 1;
    while lo < hi do
    begin
      a := PA_U8(base + lo);
      b := PA_U8(base + hi);
      t := a^; a^ := b^; b^ := t;
      Inc(lo);
      Dec(hi);
    end;
  end;
  k := 0;   { silence the unused-variable warning without changing the loop }
end;

function array_.at(i: Integer): Variant;
var p: NativeInt;
begin
  p := ByteAt(i);
  if FIsFloat then
  begin
    if itemsize = 4 then Result := PA_F32(p)^ else Result := PA_F64(p)^;
    Exit;
  end;
  if FSigned then
    case itemsize of
      1: Result := PA_I8(p)^;
      2: Result := PA_I16(p)^;
      4: Result := PA_I32(p)^;
    else Result := PA_I64(p)^;
    end
  else
    case itemsize of
      1: Result := PA_U8(p)^;
      2: Result := PA_U16(p)^;
      4: Result := PA_U32(p)^;
    else Result := Int64(PA_U64(p)^);
    end;
end;

procedure array_.put(i: Integer; const v: Variant);
var p: NativeInt; iv: Int64;
begin
  p := ByteAt(i);
  if FIsFloat then
  begin
    if itemsize = 4 then PA_F32(p)^ := Double(v) else PA_F64(p)^ := Double(v);
    Exit;
  end;
  { CPython raises OverflowError when a value does not fit the typecode. We
    TRUNCATE, which is the one place this shim is knowingly laxer: refusing
    would mean a range table per typecode and audio.py already clamps its own
    samples before storing them. Recorded rather than hidden. }
  iv := Int64(v);
  case itemsize of
    1: PA_U8(p)^ := Byte(iv and $FF);
    2: PA_U16(p)^ := Word(iv and $FFFF);
    4: PA_U32(p)^ := LongWord(iv and $FFFFFFFF);
  else PA_I64(p)^ := iv;
  end;
end;

end.
