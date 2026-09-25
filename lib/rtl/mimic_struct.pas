{ SPDX-License-Identifier: Zlib }
unit mimic_struct;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `struct` module — fixed-width binary packing and unpacking.

  `import struct` RESOLVES here through the NilPy import resolver's `mimic_`
  fallback, so no file in the tree carries the stdlib's name and `--no-shims`
  can turn the substitution into an error. See devdocs/dev/python-compat-tiers.md.

  WHY A PASCAL SHIM AND NOT A `.py` ONE. The resolver is indifferent — it looks
  for `lib/rtl/mimic_struct.{pas,py}` and does not care which it finds; that
  indifference is what makes this module cheap, and `mimic_bisect` and
  `mimic_copy` next door really are Python. This one cannot be. The entire job
  is reinterpreting bytes as fixed-width numbers, and pure Python can only do
  that by hand-rolling IEEE-754 in the one language that has no way to look at
  a float's bits — which is a numerically delicate 200 lines that would then
  need its own oracle. Pascal does it with a pointer cast.

  THE TYPECODE TABLE IS NOT HERE. It lives in `mimic_array`'s `PyTypecode` and
  this unit uses it. Our fixed widths ARE struct's standard sizes — `l` is 4
  bytes here and 4 under any byte-order prefix in CPython — so one table really
  does serve both, and copying twelve rows would have put mimic_array's
  divergence note in two files with no way to notice when they stop agreeing.

  ## The subset, measured rather than guessed

  Everything below comes from the only two modules in lekkerzeilen that import
  struct (`world.py`, `capture.py`), and nothing beyond them:

    prefixes   <  >  =  !  @      (and no prefix)
    codes      b B h H i I l L q Q f d
    counts     a repeat count before a code, INCLUDING one built at run time —
               `struct.unpack("<%df" % (len(verts) // 4), verts)`. The format is
               not a literal, so a compile-time format parser in the frontend
               was never an option; this parses at run time, as CPython does.

  ABSENT, and each would be a hard error rather than a wrong answer: `s`/`p`
  (byte strings), `?` (bool), `c` (char), `n`/`N`/`P` (native-size ints),
  `e` (half floats), `x` (pad bytes), and `iter_unpack`.
  `pack_into` joined the module 2026-09-25, for MicroPython's umqtt.simple
  (`struct.pack_into("!H", pkt, 2, pid)`); it is still absent on Struct.
  `unpack_from` was in that list until 2026-09-19, when That Space Program's
  ephemeris reader needed it; it is below now, on the module and on Struct. Adding any of them is a small edit to ItemSize and the two
  loops; leaving them out is not a design, just an unmet need.

  The `Struct` CLASS was in that list until 2026-09-13, when lekkerzeilen's
  new `facades.py` opened with `HEADER = struct.Struct("<IIIII")` and the
  build stopped at `no member Struct came of the qualifier struct`. It is
  below now.

  ## `=` IS NOT `<`, AND THAT IS THE WHOLE POINT OF THIS MODULE IN world.py

  world.py's only use of struct is to ask whether the host is little-endian:

      _LE = struct.pack("<h", 1) == struct.pack("=h", 1)

  A shim that treated `=` as `<` would make that comparison a tautology and
  answer "little-endian, never swap" on a big-endian host — then decode every
  terrain file backwards, silently, and only there. So `=`/`@`/no-prefix are
  resolved against the ACTUAL host order, probed at run time by looking at the
  bytes of a Word, and not against an assumption. On x86-64 the two agree and
  this costs nothing; on the aarch64-BE and the s390-shaped targets in the
  cross matrix it is the difference between working and quietly wrong.

  ## `@` DOES NOT PAD HERE, AND CPYTHON'S DOES — a stated divergence

  In CPython `@` (which is also the default when no prefix is given) means
  native size AND native ALIGNMENT, so `struct.pack("@ci", b"x", 1)` inserts
  three pad bytes. We treat `@` exactly as `=`: native order, standard sizes,
  no padding. It matters only for a format mixing widths with no prefix, which
  is a shape that appears nowhere in the corpus and is one nobody writes
  deliberately for a file format — a program that cares about the layout says
  so with `<` or `>`. Recorded as a divergence rather than a subset because it
  produces a DIFFERENT ANSWER rather than an error, which is the kind worth
  saying out loud. }

interface

uses pylib, sysutils, mimic_array;

type
  { struct.error. CPython raises it for a bad format and for a length mismatch,
    and real code catches it by name -- so it is a distinct class rather than a
    bare Exception, even though the corpus never catches one. }
  error = class(Exception);

  { Reinterpretation pointers, declared here rather than assumed from the RTL
    so this unit states its own requirements. }
  PS_U8  = ^Byte;
  PS_I16 = ^SmallInt;   PS_U16 = ^Word;
  PS_I32 = ^LongInt;    PS_U32 = ^LongWord;
  PS_I64 = ^Int64;      PS_U64 = ^QWord;
  PS_F32 = ^Single;     PS_F64 = ^Double;

function calcsize(const fmt: AnsiString): Integer;

{ pack(fmt, *args). ONE implementation over a TPyList, plus thin arity
  overloads, because Pascal has no *args and NilPy does not synthesise one.
  Seven is not arbitrary: capture.py's `">IIBBBBB"` is the widest call in the
  corpus. An eighth is one line.

  Arity is the only thing separating these, which is the safe discriminator —
  bug-n-an-overloaded-constructor-is-picked-by-name-ignoring-argument-type says
  a CONSTRUCTOR overload set is chosen by name and first match; ordinary
  function overloads resolve correctly, and these differ in count anyway. }
function pack(const fmt: AnsiString; const a1: Variant): TPyBytes; overload;
function pack(const fmt: AnsiString; const a1, a2: Variant): TPyBytes; overload;
function pack(const fmt: AnsiString; const a1, a2, a3: Variant): TPyBytes; overload;
function pack(const fmt: AnsiString; const a1, a2, a3, a4: Variant): TPyBytes; overload;
function pack(const fmt: AnsiString;
              const a1, a2, a3, a4, a5: Variant): TPyBytes; overload;
function pack(const fmt: AnsiString;
              const a1, a2, a3, a4, a5, a6: Variant): TPyBytes; overload;
function pack(const fmt: AnsiString;
              const a1, a2, a3, a4, a5, a6, a7: Variant): TPyBytes; overload;
{ ...and the list form, which is what every overload above funnels into. Public
  because a NilPy program with a run-time-sized argument list can also reach it
  directly, and because `pack` below delegates to it. }
function pack_list(const fmt: AnsiString; args: TPyList): TPyBytes;

{ THE *args ARM, and the reason the ladder above is no longer the whole story.
  `{$PYSTAR}` says: the LAST parameter of the declaration that follows is the
  Python `*args` collector, so `pack(fmt, *values)` packs the starred run into
  it — one call, any length — instead of dispatching on len(values) against one
  rung of the ladder.

  THE LADDER CANNOT DO THIS AT ANY WIDTH, which is why the marker exists rather
  than an eighth overload. lekkerzeilen's gfx.py does
  `struct.pack("<%df" % len(values), *values)` over a whole VERTEX BUFFER, so
  the count is unbounded and a `got 3000 arguments, expected 2 to 2` is the same
  failure however far the rungs go.

  The ladder STAYS and keeps its callers: the promotion to this overload is
  gated on a star element being present, so `pack(fmt, 1.0, 2.0)` resolves
  exactly as before. It also stays because the PINNED compiler ignores
  `{$PYSTAR}` (with a warning) and knows nothing about the promotion — under the
  pin this is just another overload nobody calls, and the ladder is still what
  serves every written-out call. }
{$PYSTAR}
function pack(const fmt: AnsiString; args: TPyList): TPyBytes; overload;

{ unpack(fmt, buf) -> tuple. A TPyList tagged PYSEQ_TUPLE: list, tuple and set
  are one class here and the Python type is a runtime tag, so this really is a
  tuple to repr(), type() and isinstance(). }
function unpack(const fmt: AnsiString; b: TPyBytes): TPyList;

{ unpack_from(fmt, buf, offset=0) -> tuple: the format's bytes read AT `offset`,
  and the buffer may be longer than that. A negative offset counts from the end,
  as CPython's does. That Space Program's SPK ephemeris reader is built on it: it
  walks a 32 MB file of fixed-width records with one call per record and never
  slices. The buffer is what `mmap.mmap` hands back, which is a TPyBytes here
  (mimic_mmap), so the one signature serves both. }
function unpack_from(const fmt: AnsiString; b: TPyBytes; offset: Integer = 0): TPyList;

{ pack_into(fmt, buffer, offset, v1, ...) -- pack() written INTO a bytearray at
  `offset` instead of returned. Same ladder-plus-*args shape as pack, for the
  same reason; each funnels into pack_into_list. A negative offset counts from
  the end, and the three range errors are CPython's words. }
procedure pack_into_list(const fmt: AnsiString; buf: TPyBytes; offset: Integer; args: TPyList);
procedure pack_into(const fmt: AnsiString; buf: TPyBytes; offset: Integer;
                    const a1: Variant); overload;
procedure pack_into(const fmt: AnsiString; buf: TPyBytes; offset: Integer;
                    const a1, a2: Variant); overload;
procedure pack_into(const fmt: AnsiString; buf: TPyBytes; offset: Integer;
                    const a1, a2, a3: Variant); overload;
procedure pack_into(const fmt: AnsiString; buf: TPyBytes; offset: Integer;
                    const a1, a2, a3, a4: Variant); overload;
{$PYSTAR}
procedure pack_into(const fmt: AnsiString; buf: TPyBytes; offset: Integer;
                    args: TPyList); overload;

type
  { struct.Struct(fmt) -- one format, parsed once and reused.

    CPython's Struct exists for speed: the format is compiled at construction
    instead of at every call. Here it is a convenience with the same SURFACE,
    because the parse is a walk over a five-character string either way -- so
    what a caller can observe is identical, and that is the whole contract.

    `size` is a plain field rather than a re-walk, which is the one place the
    caching is visible: facades.py reads `HEADER.size` twice per file it
    opens, once to size the read and once to check it came back whole.

    The four names below are every attribute of CPython's Struct that the
    corpus reaches, plus `unpack_from` (see the module-level one). `pack_into`
    and `iter_unpack` stay absent
    on the class for the same reason they are absent at module level: nothing
    calls them, and a missing member is a compile error where a guess would
    be a wrong file. }
  Struct = class
  public
    format: AnsiString;
    size: Integer;
    constructor Create(const fmt: AnsiString);
    { The same arity ladder the module-level `pack` carries, and for the same
      reason: this dialect has no *args. Each one funnels into pack_list. }
    function pack(const a1: Variant): TPyBytes; overload;
    function pack(const a1, a2: Variant): TPyBytes; overload;
    function pack(const a1, a2, a3: Variant): TPyBytes; overload;
    function pack(const a1, a2, a3, a4: Variant): TPyBytes; overload;
    function pack(const a1, a2, a3, a4, a5: Variant): TPyBytes; overload;
    function pack(const a1, a2, a3, a4, a5, a6: Variant): TPyBytes; overload;
    function pack(const a1, a2, a3, a4, a5, a6, a7: Variant): TPyBytes; overload;
    { ...and the *args arm, the class twin of the module-level one. See the
      `{$PYSTAR}` note above `pack` in the interface for why the marker exists
      and why the ladder stays beside it. }
    {$PYSTAR}
    function pack(args: TPyList): TPyBytes; overload;
    function pack_list(args: TPyList): TPyBytes;
    function unpack(b: TPyBytes): TPyList;
    function unpack_from(b: TPyBytes; offset: Integer = 0): TPyList;
  end;

implementation

{ Host byte order, probed rather than assumed. A `{$IFDEF ENDIAN_LITTLE}` would
  be resolved by the compiler building this unit, which is right for a native
  build and wrong the moment lib/rtl is compiled once and used for a
  cross-target — and this module's whole job is to be correct about byte order. }
function HostIsLE: Boolean;
var w: Word;
begin
  w := 1;
  HostIsLE := PS_U8(@w)^ = 1;
end;

{ Split the prefix off a format. Returns the index of the first code character
  and sets `swap` to whether the bytes we lay down must be reversed. }
procedure FmtPrefix(const fmt: AnsiString; var i: Integer; var swap: Boolean);
begin
  i := 1;
  swap := False;
  if Length(fmt) = 0 then Exit;
  case fmt[1] of
    '<': begin swap := not HostIsLE; i := 2; end;
    '>': begin swap := HostIsLE; i := 2; end;
    '!': begin swap := HostIsLE; i := 2; end;   { network order == big-endian }
    '=': i := 2;                                { native order; see the header }
    '@': i := 2;                                { native order, and see the
                                                  no-padding divergence above }
  end;
end;

{ The size of one item of code `c`, or 0 -- the caller raises, because the
  message a user expects depends on which module they called. }
function ItemSize(c: Char): Integer;
var n: Integer; f, sg: Boolean;
begin
  n := 0;
  { `u` is array's Py_UCS4 and is NOT a struct code; PyTypecode knows it, so it
    is refused here rather than silently accepted as a 4-byte unsigned. One
    shared table, two vocabularies -- sharing the widths does not mean sharing
    the alphabet. }
  if (c = 'u') or not PyTypecode(c, n, f, sg) then n := 0;
  ItemSize := n;
end;

function IsFloatCode(c: Char): Boolean;
begin
  IsFloatCode := (c = 'f') or (c = 'd');
end;

function IsSignedCode(c: Char): Boolean;
var n: Integer; f, sg: Boolean;
begin
  n := 0; f := False; sg := True;
  if not PyTypecode(c, n, f, sg) then sg := True;
  IsSignedCode := sg;
end;

{ Walk a format, calling back into the caller's loop via the two out-params.
  Written as an explicit cursor rather than a callback because {$MODE PXX} has
  no closures and three copies of "parse a count then a code" is exactly the
  second path that stays broken. `count` is 1 when no digits precede the code. }
function NextItem(const fmt: AnsiString; var i: Integer;
                  var code: Char; var count: Integer): Boolean;
var d: Integer;
begin
  NextItem := False;
  if i > Length(fmt) then Exit;
  { skip whitespace, which CPython allows between items }
  while (i <= Length(fmt)) and (fmt[i] = ' ') do Inc(i);
  if i > Length(fmt) then Exit;
  d := 0;
  count := -1;
  while (i <= Length(fmt)) and (fmt[i] >= '0') and (fmt[i] <= '9') do
  begin
    { A repeat count is the thing world.py builds at run time -- `"<%df" % n`
      with n in the thousands -- so this must be a real integer parse and not a
      single digit. The first draft read one digit and would have decoded 3 of
      3000 vertices, silently, with no error anywhere. }
    d := d * 10 + (Ord(fmt[i]) - Ord('0'));
    count := d;
    Inc(i);
  end;
  if i > Length(fmt) then
    raise error.Create('repeat count with no format code after it');
  if count < 0 then count := 1;
  code := fmt[i];
  Inc(i);
  NextItem := True;
end;

function calcsize(const fmt: AnsiString): Integer;
var i, n, cnt, sz: Integer; swap: Boolean; c: Char;
begin
  FmtPrefix(fmt, i, swap);
  n := 0;
  c := ' ';
  cnt := 0;
  while NextItem(fmt, i, c, cnt) do
  begin
    sz := ItemSize(c);
    if sz = 0 then
      raise error.Create('bad char in struct format: ' + c);
    n := n + sz * cnt;
  end;
  calcsize := n;
end;

{ Lay `sz` bytes of `src` into `dst` at `off`, reversing if the target order is
  not the host's. One place, so a byte-order bug can only exist once. }
procedure PutBytes(dst: PS_U8; off: Integer; src: PS_U8; sz: Integer;
                   swap: Boolean);
var k: Integer; d, s: PS_U8;
begin
  for k := 0 to sz - 1 do
  begin
    d := PS_U8(NativeInt(dst) + off + k);
    if swap then s := PS_U8(NativeInt(src) + (sz - 1 - k))
            else s := PS_U8(NativeInt(src) + k);
    d^ := s^;
  end;
end;

function pack_list(const fmt: AnsiString; args: TPyList): TPyBytes;
var i, off, cnt, sz, k, ai: Integer;
    swap, isf: Boolean;
    c: Char;
    total: Integer;
    iv: Int64;
    dv: Double;
    f32: Single;
    i16: SmallInt; u16: Word;
    i32: LongInt; u32: LongWord;
    i64: Int64;   u64: QWord;
    b8: Byte;
    outp: PS_U8;
    res: TPyBytes;
begin
  total := calcsize(fmt);
  { A LOCAL and not the function name. `pack_list.FData` reads the result as a
    value, and a function name in an expression is a recursive CALL in Pascal --
    the ambiguity Result exists to remove. Assigned once at the end. }
  res := TPyBytes.Create(total);
  outp := PS_U8(res.FData);
  FmtPrefix(fmt, i, swap);
  off := 0;
  ai := 0;
  c := ' ';
  cnt := 0;
  while NextItem(fmt, i, c, cnt) do
  begin
    sz := ItemSize(c);
    isf := IsFloatCode(c);
    for k := 1 to cnt do
    begin
      if ai >= len(args) then
        raise error.Create('pack expected more arguments than were given');
      if isf then
      begin
        dv := Double(args.at(ai));
        if sz = 4 then
        begin
          f32 := dv;
          PutBytes(outp, off, PS_U8(@f32), 4, swap);
        end
        else
          PutBytes(outp, off, PS_U8(@dv), 8, swap);
      end
      else
      begin
        { Through Int64 whatever the width, then narrowed by the typed local.
          The narrowing is the WRAPPING CPython does for the unsigned codes and
          the range error it raises for the signed ones; we wrap in both
          directions, which accepts what CPython rejects and is therefore
          laxity rather than a defect -- the upward-compatibility direction. }
        iv := Int64(args.at(ai));
        case sz of
          1: begin b8 := Byte(iv and $FF); PutBytes(outp, off, PS_U8(@b8), 1, swap); end;
          2: if IsSignedCode(c) then
             begin i16 := SmallInt(iv); PutBytes(outp, off, PS_U8(@i16), 2, swap); end
             else
             begin u16 := Word(iv); PutBytes(outp, off, PS_U8(@u16), 2, swap); end;
          4: if IsSignedCode(c) then
             begin i32 := LongInt(iv); PutBytes(outp, off, PS_U8(@i32), 4, swap); end
             else
             begin u32 := LongWord(iv); PutBytes(outp, off, PS_U8(@u32), 4, swap); end;
          8: if IsSignedCode(c) then
             begin i64 := iv; PutBytes(outp, off, PS_U8(@i64), 8, swap); end
             else
             begin u64 := QWord(iv); PutBytes(outp, off, PS_U8(@u64), 8, swap); end;
        end;
      end;
      off := off + sz;
      Inc(ai);
    end;
  end;
  { CPython raises for too FEW arguments and also for too many. Both are
    programmer errors that produce a silently short or silently ignored record
    if we let them pass, and a binary format is the worst place to find out
    later. }
  if ai <> len(args) then
    raise error.Create('pack expected ' + IntToStr(ai) + ' argument(s), got '
                       + IntToStr(len(args)));
  pack_list := res;
end;

{ The `*args` arm — see the `{$PYSTAR}` note in the interface. A straight
  delegation: the collector IS the argument list pack_list already takes. }
function pack(const fmt: AnsiString; args: TPyList): TPyBytes;
begin
  pack := pack_list(fmt, args);
end;

function pack(const fmt: AnsiString; const a1: Variant): TPyBytes;
var l: TPyList;
begin
  l := TPyList.Create; l.append(a1); pack := pack_list(fmt, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

function pack(const fmt: AnsiString; const a1, a2: Variant): TPyBytes;
var l: TPyList;
begin
  l := TPyList.Create; l.append(a1); l.append(a2);
  pack := pack_list(fmt, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

function pack(const fmt: AnsiString; const a1, a2, a3: Variant): TPyBytes;
var l: TPyList;
begin
  l := TPyList.Create; l.append(a1); l.append(a2); l.append(a3);
  pack := pack_list(fmt, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

function pack(const fmt: AnsiString; const a1, a2, a3, a4: Variant): TPyBytes;
var l: TPyList;
begin
  l := TPyList.Create; l.append(a1); l.append(a2); l.append(a3); l.append(a4);
  pack := pack_list(fmt, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

function pack(const fmt: AnsiString;
              const a1, a2, a3, a4, a5: Variant): TPyBytes;
var l: TPyList;
begin
  l := TPyList.Create;
  l.append(a1); l.append(a2); l.append(a3); l.append(a4); l.append(a5);
  pack := pack_list(fmt, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

function pack(const fmt: AnsiString;
              const a1, a2, a3, a4, a5, a6: Variant): TPyBytes;
var l: TPyList;
begin
  l := TPyList.Create;
  l.append(a1); l.append(a2); l.append(a3);
  l.append(a4); l.append(a5); l.append(a6);
  pack := pack_list(fmt, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

function pack(const fmt: AnsiString;
              const a1, a2, a3, a4, a5, a6, a7: Variant): TPyBytes;
var l: TPyList;
begin
  l := TPyList.Create;
  l.append(a1); l.append(a2); l.append(a3); l.append(a4);
  l.append(a5); l.append(a6); l.append(a7);
  pack := pack_list(fmt, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

{ Read `sz` bytes out of `src` at `off` into `dst`, un-reversing if needed. The
  mirror of PutBytes, and deliberately a second function rather than a flag on
  the first: the two differ in which side the reversal applies to, and one
  function with a direction flag is where that gets confused. }
procedure GetBytes(dst: PS_U8; src: PS_U8; off, sz: Integer; swap: Boolean);
var k: Integer; d, s: PS_U8;
begin
  for k := 0 to sz - 1 do
  begin
    s := PS_U8(NativeInt(src) + off + k);
    if swap then d := PS_U8(NativeInt(dst) + (sz - 1 - k))
            else d := PS_U8(NativeInt(dst) + k);
    d^ := s^;
  end;
end;

{ The decode loop both entry points share: `fmt`'s items read from `b` starting
  at byte `base`. The CALLER has checked that they fit, because the two
  entries need different checks and different messages (unpack wants the
  sizes EQUAL, unpack_from only wants them to fit). }
function DecodeAt(const fmt: AnsiString; b: TPyBytes; base: Integer): TPyList;
var i, off, cnt, sz, k: Integer;
    swap, isf: Boolean;
    c: Char;
    f32: Single; f64: Double;
    i16: SmallInt; u16: Word;
    i32: LongInt; u32: LongWord;
    i64: Int64;   u64: QWord;
    b8: Byte;
    inp: PS_U8;
    res: TPyList;
begin
  res := TPyList.Create;
  { A TUPLE, not a list. One representation, three Python types, and the kind is
    a runtime tag (PYSEQ_TUPLE) -- so this costs one assignment and is the
    difference between `(1234567,)` and `[1234567]` when a program PRINTS the
    result. Both corpus call sites wrap this in list(...) and would never have
    noticed, which is exactly why it is worth setting: the next caller prints
    it, and a repr that silently disagrees with CPython is the kind of
    divergence that gets found in someone else's output diff. }
  res.FKind := PYSEQ_TUPLE;
  inp := PS_U8(b.FData);
  FmtPrefix(fmt, i, swap);
  off := base;
  c := ' ';
  cnt := 0;
  while NextItem(fmt, i, c, cnt) do
  begin
    sz := ItemSize(c);
    isf := IsFloatCode(c);
    for k := 1 to cnt do
    begin
      if isf then
      begin
        if sz = 4 then
        begin
          GetBytes(PS_U8(@f32), inp, off, 4, swap);
          res.append(Double(f32));
        end
        else
        begin
          GetBytes(PS_U8(@f64), inp, off, 8, swap);
          res.append(f64);
        end;
      end
      else
      begin
        case sz of
          1: begin
               GetBytes(PS_U8(@b8), inp, off, 1, swap);
               if IsSignedCode(c) then res.append(Int64(ShortInt(b8)))
                                  else res.append(Int64(b8));
             end;
          2: if IsSignedCode(c) then
             begin GetBytes(PS_U8(@i16), inp, off, 2, swap); res.append(Int64(i16)); end
             else
             begin GetBytes(PS_U8(@u16), inp, off, 2, swap); res.append(Int64(u16)); end;
          4: if IsSignedCode(c) then
             begin GetBytes(PS_U8(@i32), inp, off, 4, swap); res.append(Int64(i32)); end
             else
             begin GetBytes(PS_U8(@u32), inp, off, 4, swap); res.append(Int64(u32)); end;
          8: if IsSignedCode(c) then
             begin GetBytes(PS_U8(@i64), inp, off, 8, swap); res.append(i64); end
             else
             begin GetBytes(PS_U8(@u64), inp, off, 8, swap); res.append(Int64(u64)); end;
        end;
      end;
      off := off + sz;
    end;
  end;
  DecodeAt := res;
end;

function unpack(const fmt: AnsiString; b: TPyBytes): TPyList;
var need: Integer;
begin
  need := calcsize(fmt);
  { CPython's message names both numbers and so does this one. A length
    mismatch here is almost always a format that drifted from the writer's, and
    the two sizes are what tells you which end moved. }
  if b.FLen <> need then
    raise error.Create('unpack requires a buffer of ' + IntToStr(need)
                       + ' bytes, got ' + IntToStr(b.FLen));
  unpack := DecodeAt(fmt, b, 0);
end;

procedure pack_into_list(const fmt: AnsiString; buf: TPyBytes; offset: Integer; args: TPyList);
var raw: TPyBytes; need, at: Integer;
begin
  need := calcsize(fmt);
  at := offset;
  if at < 0 then
  begin
    if at + buf.FLen < 0 then
      raise error.Create('offset ' + IntToStr(offset) + ' out of range for '
                         + IntToStr(buf.FLen) + '-byte buffer');
    at := at + buf.FLen;
    if at + need > buf.FLen then
      raise error.Create('no space to pack ' + IntToStr(need)
                         + ' bytes at offset ' + IntToStr(offset));
  end
  else if at + need > buf.FLen then
    raise error.Create('pack_into requires a buffer of at least '
                       + IntToStr(at + need) + ' bytes for packing '
                       + IntToStr(need) + ' bytes at offset ' + IntToStr(at)
                       + ' (actual buffer size is ' + IntToStr(buf.FLen) + ')');
  raw := pack_list(fmt, args);
  if need > 0 then Move(raw.FData^, (PByte(buf.FData) + at)^, need);
  PXXObjRelease(Pointer(raw));
end;

procedure pack_into(const fmt: AnsiString; buf: TPyBytes; offset: Integer;
                    const a1: Variant);
var l: TPyList;
begin
  l := TPyList.Create; l.append(a1);
  pack_into_list(fmt, buf, offset, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

procedure pack_into(const fmt: AnsiString; buf: TPyBytes; offset: Integer;
                    const a1, a2: Variant);
var l: TPyList;
begin
  l := TPyList.Create; l.append(a1); l.append(a2);
  pack_into_list(fmt, buf, offset, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

procedure pack_into(const fmt: AnsiString; buf: TPyBytes; offset: Integer;
                    const a1, a2, a3: Variant);
var l: TPyList;
begin
  l := TPyList.Create; l.append(a1); l.append(a2); l.append(a3);
  pack_into_list(fmt, buf, offset, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

procedure pack_into(const fmt: AnsiString; buf: TPyBytes; offset: Integer;
                    const a1, a2, a3, a4: Variant);
var l: TPyList;
begin
  l := TPyList.Create; l.append(a1); l.append(a2); l.append(a3); l.append(a4);
  pack_into_list(fmt, buf, offset, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

procedure pack_into(const fmt: AnsiString; buf: TPyBytes; offset: Integer;
                    args: TPyList);
begin
  pack_into_list(fmt, buf, offset, args);
end;

{ CPython's three messages, word for word: a negative offset past the start, a
  negative offset whose item runs off the end, and a non-negative one that does. }
function unpack_from(const fmt: AnsiString; b: TPyBytes; offset: Integer = 0): TPyList;
var need, at: Integer;
begin
  need := calcsize(fmt);
  at := offset;
  if at < 0 then
  begin
    if at + b.FLen < 0 then
      raise error.Create('offset ' + IntToStr(offset) + ' out of range for '
                         + IntToStr(b.FLen) + '-byte buffer');
    at := at + b.FLen;
    if at + need > b.FLen then
      raise error.Create('not enough data to unpack ' + IntToStr(need)
                         + ' bytes at offset ' + IntToStr(offset));
  end
  else if at + need > b.FLen then
    raise error.Create('unpack_from requires a buffer of at least '
                       + IntToStr(at + need) + ' bytes for unpacking '
                       + IntToStr(need) + ' bytes at offset ' + IntToStr(at)
                       + ' (actual buffer size is ' + IntToStr(b.FLen) + ')');
  unpack_from := DecodeAt(fmt, b, at);
end;

{ ------------------------------------------------------------- Struct ---- }

{ The class methods are named `pack`, `pack_list` and `unpack` -- the Python
  spelling -- and so are the unit-level functions they delegate to. A method
  name hides the unit-level one throughout the method body, so calling
  `pack_list(format, l)` from inside Struct.pack would be an arity error
  against the METHOD rather than a call to the function. These two aliases sit
  at unit level, where only the functions are in scope, and are the whole of
  the indirection. }
function StructPackList(const fmt: AnsiString; args: TPyList): TPyBytes;
begin
  StructPackList := pack_list(fmt, args);
end;

function StructUnpack(const fmt: AnsiString; b: TPyBytes): TPyList;
begin
  StructUnpack := unpack(fmt, b);
end;

function StructUnpackFrom(const fmt: AnsiString; b: TPyBytes; offset: Integer): TPyList;
begin
  StructUnpackFrom := unpack_from(fmt, b, offset);
end;

constructor Struct.Create(const fmt: AnsiString);
begin
  inherited Create;
  { calcsize RAISES on a bad code, which is what CPython does at construction
    too -- `struct.Struct("<z")` is an error there and then, not at the first
    pack. So the size computation doubles as the format check and there is no
    second validator to drift from this one. }
  format := fmt;
  size := calcsize(fmt);
end;

{ The *args arm — the collector IS the argument list pack_list already takes. }
function Struct.pack(args: TPyList): TPyBytes;
begin
  pack := pack_list(args);
end;

function Struct.pack_list(args: TPyList): TPyBytes;
begin
  Result := StructPackList(format, args);
end;

function Struct.unpack(b: TPyBytes): TPyList;
begin
  Result := StructUnpack(format, b);
end;

function Struct.unpack_from(b: TPyBytes; offset: Integer = 0): TPyList;
begin
  Result := StructUnpackFrom(format, b, offset);
end;

function Struct.pack(const a1: Variant): TPyBytes;
var l: TPyList;
begin
  l := TPyList.Create; l.append(a1); Result := StructPackList(format, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

function Struct.pack(const a1, a2: Variant): TPyBytes;
var l: TPyList;
begin
  l := TPyList.Create; l.append(a1); l.append(a2);
  Result := StructPackList(format, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

function Struct.pack(const a1, a2, a3: Variant): TPyBytes;
var l: TPyList;
begin
  l := TPyList.Create; l.append(a1); l.append(a2); l.append(a3);
  Result := StructPackList(format, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

function Struct.pack(const a1, a2, a3, a4: Variant): TPyBytes;
var l: TPyList;
begin
  l := TPyList.Create; l.append(a1); l.append(a2); l.append(a3); l.append(a4);
  Result := StructPackList(format, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

function Struct.pack(const a1, a2, a3, a4, a5: Variant): TPyBytes;
var l: TPyList;
begin
  l := TPyList.Create;
  l.append(a1); l.append(a2); l.append(a3); l.append(a4); l.append(a5);
  Result := StructPackList(format, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

function Struct.pack(const a1, a2, a3, a4, a5, a6: Variant): TPyBytes;
var l: TPyList;
begin
  l := TPyList.Create;
  l.append(a1); l.append(a2); l.append(a3);
  l.append(a4); l.append(a5); l.append(a6);
  Result := StructPackList(format, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

function Struct.pack(const a1, a2, a3, a4, a5, a6, a7: Variant): TPyBytes;
var l: TPyList;
begin
  l := TPyList.Create;
  l.append(a1); l.append(a2); l.append(a3); l.append(a4);
  l.append(a5); l.append(a6); l.append(a7);
  Result := StructPackList(format, l); PXXObjRelease(Pointer(l));   { the ladder's own list }
end;

end.
