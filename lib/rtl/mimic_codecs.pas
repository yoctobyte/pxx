{ SPDX-License-Identifier: Zlib }
unit mimic_codecs;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `codecs` module — the subset that the html5lib dependency ladder
  starts on.

  `import codecs` RESOLVES here through the NilPy import resolver's `mimic_`
  fallback, so no file in the tree carries the stdlib's name and `--no-shims`
  can turn the substitution into an error. See devdocs/dev/python-compat-tiers.md.

  THE SUBSET, stated plainly: the charmap trio, the codec registry, and the five
  base classes — measured against what `webencodings` actually touches, not
  guessed at from the module's index. What is NOT here: the stream classes do
  no streaming (they are the inheritance anchors CPython uses them as, and
  webencodings never reads or writes through them), `open`/`EncodedFile` are
  absent, and the error policies are the three a charmap codec can implement
  (`strict`, `replace`, `ignore`) rather than the full registry of handlers.

  The registry is seeded with the encodings this RTL can actually perform.
  `lookup` on anything else raises LookupError, which is what CPython does and
  is a great deal better than answering with a codec that silently mangles.

  Note on tables: CPython's `charmap_build` answers with an opaque EncodingMap
  and `charmap_encode` takes it straight back, so nothing portable inspects it.
  Here it is a dict from CODE POINT to byte, which is that contract and is also
  readable in a debugger. }

interface

uses pylib, sysutils;

type
  { `codecs.Codec` — CPython's is a pair of abstract methods a codec overrides.
    Nothing calls through the base (a subclass that failed to override would be
    a broken codec, not a working one taking a default), so the base carries no
    behaviour and exists to be inherited, which is exactly its CPython role. }
  Codec = class
  public
    constructor Create;
  end;

  { `codecs.IncrementalEncoder(errors='strict')` / `IncrementalDecoder`. These
    two DO carry state: the constructor stores `errors`, and a subclass's
    `encode`/`decode` reads `self.errors` without defining `__init__` — which
    is precisely how webencodings' x-user-defined codec is written. }
  IncrementalEncoder = class
  public
    errors: AnsiString;
    constructor Create(const errors: AnsiString = 'strict');
    procedure reset;
  end;

  IncrementalDecoder = class
  public
    errors: AnsiString;
    constructor Create(const errors: AnsiString = 'strict');
    procedure reset;
  end;

  { `codecs.StreamReader` / `StreamWriter` — inheritance anchors only, see the
    header. A codec module declares them so that `codecs.lookup` can hand them
    out; a caller that wants streaming is out of this subset. }
  StreamReader = class
  public
    stream: Variant;
    errors: AnsiString;
    constructor Create(const stream: Variant = 0; const errors: AnsiString = 'strict');
  end;

  StreamWriter = class
  public
    stream: Variant;
    errors: AnsiString;
    constructor Create(const stream: Variant = 0; const errors: AnsiString = 'strict');
  end;

  { `codecs.CodecInfo(name=..., encode=..., decode=..., ...)`. CPython's is a
    tuple subclass with named attributes; the attribute half is what every
    caller in this ladder uses (`ci.decode(...)`, `ci.incrementaldecoder(errs)`),
    and the tuple half is reachable through `as_tuple` rather than by indexing —
    a class here cannot be a sequence too.

    Every callable member is a Variant because the values are Python objects:
    `encode=Codec().encode` is a BOUND METHOD and `incrementaldecoder=SomeClass`
    is a CLASS, called later to construct. Both round-trip through a Variant. }
  CodecInfo = class
  public
    name: AnsiString;
    encode: Variant;
    decode: Variant;
    incrementalencoder: Variant;
    incrementaldecoder: Variant;
    streamreader: Variant;
    streamwriter: Variant;
    constructor Create(const encode: Variant = 0; const decode: Variant = 0;
                       const streamreader: Variant = 0;
                       const streamwriter: Variant = 0;
                       const incrementalencoder: Variant = 0;
                       const incrementaldecoder: Variant = 0;
                       const name: AnsiString = '');
    { the CPython tuple face: (encode, decode, streamreader, streamwriter) }
    function as_tuple: TPyList;
  end;

{ ---- the charmap trio ---------------------------------------------------- }

{ `codecs.charmap_build(decoding_table)` — invert a 256-character decoding
  table into the map charmap_encode wants. The table is a str whose Nth
  character is what byte N decodes to; U+FFFE means "this byte is undefined",
  and CPython leaves those out of the built map, so encoding to them fails. }
function charmap_build(const decoding_table: AnsiString): TPyDict;

{ `codecs.charmap_decode(input, errors, decoding_table)` -> `(str, len(input))`.
  Answers a TUPLE, because callers write `charmap_decode(...)[0]`. }
function charmap_decode(input: TPyBytes; const errors: AnsiString;
                        const decoding_table: AnsiString): TPyList;

{ `codecs.charmap_encode(input, errors, encoding_table)` -> `(bytes, len(input))`.
  `len` counts CHARACTERS consumed, as CPython's does — not bytes produced. }
function charmap_encode(const input: AnsiString; const errors: AnsiString;
                        encoding_table: TPyDict): TPyList;

{ ---- the registry -------------------------------------------------------- }

{ `codecs.lookup(name)` — the registered codec, by normalised name. Raises
  LookupError when there is none, as CPython does.

  VARIANT, not CodecInfo: a registered search function is Python code and
  answers a Python object, which may be a CodecInfo built here or one built in
  NilPy. Typing this `CodecInfo` would force a downcast on a value we do not
  own, and callers reach it as `lookup(n).decode(...)` either way. }
function lookup(const name: AnsiString): Variant;

{ `codecs.register(search_function)` — install a search function. It is called
  with a normalised encoding name and answers a CodecInfo or None, which is how
  a library installs a codec of its own (webencodings does this for
  x-user-defined). Searches run in registration order, newest last, and the
  built-in table is consulted first. }
procedure register(const search_function: Variant);

{ `codecs.encode(obj, encoding)` / `codecs.decode(obj, encoding)` — the
  one-shot spellings, routed through the same registry. }
function encode(const input: AnsiString; const encoding: AnsiString = 'utf-8';
                const errors: AnsiString = 'strict'): TPyBytes;
function decode(input: TPyBytes; const encoding: AnsiString = 'utf-8';
                const errors: AnsiString = 'strict'): AnsiString;

{ CPython exposes the BOM constants from this module and encoding-detection
  code reaches for them by name. }
const
{ BYTES, not AnsiString, because that is what they are FOR.

  These were `AnsiString` consts, and the type was the whole bug: a BOM is a
  byte sequence a caller compares against the head of a byte string, and
  `data.startswith(codecs.BOM_UTF8)` answered False for data that begins with a
  BOM -- silently defeating exactly the encoding detection this unit's header
  says the constants exist for.

  The UTF-8 one was doubly wrong and is a nice illustration: `#$EF#$BB#$BF` is a
  well-formed UTF-8 encoding of U+FEFF, so as a string it held ONE character and
  `len()` answered 1 where CPython says 3. It looked right in every way except
  the one that matters.

  They are `var` + an initialiser in the unit's init block rather than `const`
  because a TPyBytes has to be constructed; nothing assigns to them after
  startup. }
var
  BOM_UTF8: TPyBytes;
  BOM_UTF16_LE: TPyBytes;
  BOM_UTF16_BE: TPyBytes;
  BOM_UTF32_LE: TPyBytes;
  BOM_UTF32_BE: TPyBytes;

implementation

const
  { U+FFFE in a decoding table is CPython's "no character here" marker. }
  CP_UNDEFINED = $FFFE;
  { CPython's `replace` substitutes U+FFFD when decoding and '?' when encoding —
    two different characters, and the asymmetry is deliberate: the decoded side
    has room for a replacement character, the encoded side has one byte. }
  CP_REPLACEMENT = $FFFD;

var
  { the registry: parallel arrays rather than a dict, because the values are
    CodecInfo objects and the lookup is a handful of entries walked once }
  RegNames: array of AnsiString;
  RegInfos: array of CodecInfo;
  RegCount: Integer;
  SearchFns: array of Variant;
  SearchCount: Integer;
  Seeded: Boolean;

{ ---- UTF-8 codepoint walking --------------------------------------------- }

{ The next code point in `s` starting at byte index `i` (1-based), advancing i
  past it. A malformed lead byte is answered as itself and consumes one byte,
  which keeps the walk total: this unit's job is to be a codec, not to police
  the RTL's own strings. }
function CpAt(const s: AnsiString; var i: Integer): Integer;
var b, n, k, cp: Integer;
begin
  b := Ord(s[i]);
  if b < $80 then
  begin
    Inc(i);
    CpAt := b;
    Exit;
  end;
  if (b and $E0) = $C0 then begin n := 1; cp := b and $1F; end
  else if (b and $F0) = $E0 then begin n := 2; cp := b and $0F; end
  else if (b and $F8) = $F0 then begin n := 3; cp := b and $07; end
  else begin Inc(i); CpAt := b; Exit; end;
  if i + n > Length(s) then
  begin
    Inc(i);
    CpAt := b;
    Exit;
  end;
  for k := 1 to n do
    cp := (cp shl 6) or (Ord(s[i + k]) and $3F);
  i := i + n + 1;
  CpAt := cp;
end;

{ How many CODE POINTS `s` holds — what Python's len() answers for a str. }
function CpLen(const s: AnsiString): Integer;
var i, n: Integer;
begin
  i := 1;
  n := 0;
  while i <= Length(s) do
  begin
    CpAt(s, i);
    Inc(n);
  end;
  CpLen := n;
end;

{ ---- constructors -------------------------------------------------------- }

constructor Codec.Create;
begin
end;

constructor IncrementalEncoder.Create(const errors: AnsiString);
begin
  Self.errors := errors;
end;

procedure IncrementalEncoder.reset;
begin
  { stateless: a charmap codec carries nothing between calls }
end;

constructor IncrementalDecoder.Create(const errors: AnsiString);
begin
  Self.errors := errors;
end;

procedure IncrementalDecoder.reset;
begin
end;

constructor StreamReader.Create(const stream: Variant; const errors: AnsiString);
begin
  Self.stream := stream;
  Self.errors := errors;
end;

constructor StreamWriter.Create(const stream: Variant; const errors: AnsiString);
begin
  Self.stream := stream;
  Self.errors := errors;
end;

constructor CodecInfo.Create(const encode, decode, streamreader, streamwriter,
                             incrementalencoder, incrementaldecoder: Variant;
                             const name: AnsiString);
begin
  Self.name := name;
  Self.encode := encode;
  Self.decode := decode;
  Self.streamreader := streamreader;
  Self.streamwriter := streamwriter;
  Self.incrementalencoder := incrementalencoder;
  Self.incrementaldecoder := incrementaldecoder;
end;

function CodecInfo.as_tuple: TPyList;
var t: TPyList;
begin
  t := TPyList.Create;
  t.append(encode);
  t.append(decode);
  t.append(streamreader);
  t.append(streamwriter);
  as_tuple := tuple(t);
end;

{ ---- the charmap trio ---------------------------------------------------- }

function charmap_build(const decoding_table: AnsiString): TPyDict;
var d: TPyDict; i, b, cp: Integer;
begin
  d := TPyDict.Create;
  i := 1;
  b := 0;
  while (i <= Length(decoding_table)) and (b < 256) do
  begin
    cp := CpAt(decoding_table, i);
    { A byte the table leaves undefined must not become encodable. CPython
      omits it from the built map and charmap_encode then fails on it — the
      same reason a `replace` policy exists at all. }
    if cp <> CP_UNDEFINED then
      { FIRST wins: a table mapping two bytes to one character encodes back to
        the lower byte, which is what CPython's build does. }
      if d.indexof(cp) < 0 then d.store(cp, b);
    Inc(b);
  end;
  charmap_build := d;
end;

function charmap_decode(input: TPyBytes; const errors: AnsiString;
                        const decoding_table: AnsiString): TPyList;
var out_: AnsiString; k, i, b, cp, seen: Integer; t: TPyList;
begin
  out_ := '';
  for k := 0 to input.count - 1 do
  begin
    b := input.at(k);
    { walk the table to the b'th CODE POINT — the table is a str, so its
      characters are not its bytes }
    i := 1;
    seen := 0;
    cp := CP_UNDEFINED;
    while i <= Length(decoding_table) do
    begin
      cp := CpAt(decoding_table, i);
      if seen = b then Break;
      Inc(seen);
      cp := CP_UNDEFINED;
    end;
    if (seen <> b) then cp := CP_UNDEFINED;
    if cp = CP_UNDEFINED then
    begin
      if errors = 'ignore' then Continue
      else if errors = 'replace' then out_ := out_ + pychr_s(CP_REPLACEMENT)
      else raise UnicodeDecodeError.Create(
        'charmap: byte ' + IntToStr(b) + ' undefined in this encoding');
    end
    else
      out_ := out_ + pychr_s(cp);
  end;
  t := TPyList.Create;
  t.append(out_);
  t.append(input.count);
  charmap_decode := tuple(t);
end;

function charmap_encode(const input: AnsiString; const errors: AnsiString;
                        encoding_table: TPyDict): TPyList;
var i, cp, n, at: Integer; b: TPyBytes; acc: array of Integer; t: TPyList;
begin
  SetLength(acc, 0);
  n := 0;
  i := 1;
  while i <= Length(input) do
  begin
    cp := CpAt(input, i);
    Inc(n);
    at := encoding_table.indexof(cp);
    if at < 0 then
    begin
      if errors = 'ignore' then Continue
      else if errors = 'replace' then
      begin
        SetLength(acc, Length(acc) + 1);
        acc[Length(acc) - 1] := Ord('?');
      end
      else raise UnicodeEncodeError.Create(
        'charmap: character U+' + IntToHex(cp, 4) + ' not in this encoding');
    end
    else
    begin
      SetLength(acc, Length(acc) + 1);
      acc[Length(acc) - 1] := encoding_table.fetch(cp);
    end;
  end;
  b := TPyBytes.Create(Length(acc));
  for i := 0 to Length(acc) - 1 do
    b.put(i, acc[i]);
  t := TPyList.Create;
  t.append(b);
  t.append(n);
  charmap_encode := tuple(t);
end;

{ ---- the built-in codecs ------------------------------------------------- }

{ A single-byte table for the Latin-1 range, and the ASCII half of it. Built
  rather than written out: 256 escapes in a source file is where a typo hides. }
function Latin1Table: AnsiString;
var i: Integer; s: AnsiString;
begin
  s := '';
  for i := 0 to 255 do s := s + pychr_s(i);
  Latin1Table := s;
end;

function AsciiTable: AnsiString;
var i: Integer; s: AnsiString;
begin
  s := '';
  for i := 0 to 127 do s := s + pychr_s(i);
  { the high half is undefined, which is what makes ascii REFUSE byte 128+
    rather than quietly decode it as latin-1 }
  for i := 128 to 255 do s := s + pychr_s(CP_UNDEFINED);
  AsciiTable := s;
end;

{ `utf-8` is not a charmap and gets its own pair: NilPy strings are already
  UTF-8 internally, so encoding is a copy and decoding is a copy plus a
  validity walk. }
function Utf8Encode_(const input: AnsiString): TPyBytes;
var b: TPyBytes; i: Integer;
begin
  b := TPyBytes.Create(Length(input));
  for i := 1 to Length(input) do b.put(i - 1, Ord(input[i]));
  Utf8Encode_ := b;
end;

{ How many bytes at 0-based index `i` form a VALID utf-8 sequence, or -how
  many form its MAXIMAL SUBPART when it is invalid.

  Positive result = a good sequence of that length. Negative = invalid; negate
  it for the number of bytes to consume before emitting ONE replacement.

  The ranges are not decoration -- each one rejects a class of sequence that is
  well-formed by the naive "lead byte says N, then N-1 continuations" rule and
  is still illegal:

    C0 C1     always invalid: the only 2-byte sequences they could spell are
              overlong encodings of ASCII
    E0 A0..BF second byte floor, rejecting overlong 3-byte forms
    ED 80..9F second byte ceiling, rejecting the UTF-16 SURROGATE range, which
              is what lets a "valid utf-8" check double as a well-formedness
              check for the string that comes out
    F0 90..BF rejecting overlong 4-byte forms
    F4 80..8F rejecting everything above U+10FFFF
    F5..FF    always invalid: no code point is that high

  MAXIMAL SUBPART is Unicode's own recommendation and it is why CPython answers
  ONE replacement for a truncated-but-consistent sequence and one PER BYTE for
  a run of nonsense: b'\xe2\x82' is a single U+FFFD (two bytes that were still
  on a valid path when the input ran out), while b'\x80\x80' is two (neither
  byte can begin anything). Measured against CPython 3.12 rather than derived. }
function Utf8SeqAt(input: TPyBytes; i: Integer): Integer;
var n, b0, b1, lo, hi, need, k: Integer;
begin
  n := input.count;
  b0 := input.at(i);
  if b0 <= $7F then begin Utf8SeqAt := 1; Exit; end;
  { a continuation byte, or a lead that can never be one: nothing to walk }
  if (b0 <= $C1) or (b0 >= $F5) then begin Utf8SeqAt := -1; Exit; end;

  if b0 <= $DF then begin need := 1; lo := $80; hi := $BF; end
  else if b0 = $E0 then begin need := 2; lo := $A0; hi := $BF; end
  else if b0 = $ED then begin need := 2; lo := $80; hi := $9F; end
  else if b0 <= $EF then begin need := 2; lo := $80; hi := $BF; end
  else if b0 = $F0 then begin need := 3; lo := $90; hi := $BF; end
  else if b0 = $F4 then begin need := 3; lo := $80; hi := $8F; end
  else begin need := 3; lo := $80; hi := $BF; end;

  { the second byte carries the range restriction; the rest are plain
    continuations. Running out of input stops the walk with whatever prefix was
    still consistent -- that prefix IS the maximal subpart. }
  if i + 1 >= n then begin Utf8SeqAt := -1; Exit; end;
  b1 := input.at(i + 1);
  if (b1 < lo) or (b1 > hi) then begin Utf8SeqAt := -1; Exit; end;
  for k := 2 to need do
  begin
    if i + k >= n then begin Utf8SeqAt := -k; Exit; end;
    b1 := input.at(i + k);
    if (b1 < $80) or (b1 > $BF) then begin Utf8SeqAt := -k; Exit; end;
  end;
  Utf8SeqAt := need + 1;
end;

{ utf-8 decode WITH the error policy applied.

  This used to be `for i := ... do s := s + Chr(input.at(i))` -- a pure byte
  copy that consulted neither the input's validity nor `errors`, so all three
  policies behaved as `replace` (invalid bytes were passed through and rendered
  as U+FFFD downstream) and `strict` -- CPython's DEFAULT -- never raised. The
  unit header described "a copy plus a validity walk"; the walk did not exist.
  bug-b-codecs-strict-decode-does-not-raise-on-invalid-utf-8

  The lenient walker CpAt above is deliberately different and stays that way:
  its job is to iterate the RTL's own strings without policing them. This is
  the public codec, whose job IS to police bytes. Two callers, two contracts,
  one scanner each -- sharing them would make one of the two wrong. }
function Utf8Decode_(input: TPyBytes; const errors: AnsiString): AnsiString;
var s: AnsiString; i, L, k: Integer;
begin
  s := '';
  i := 0;
  while i < input.count do
  begin
    L := Utf8SeqAt(input, i);
    if L > 0 then
    begin
      for k := 0 to L - 1 do s := s + Chr(input.at(i + k));
      i := i + L;
    end
    else
    begin
      { 'ignore' drops the whole maximal subpart and appends nothing -- spelled
        as an explicit no-op rather than an empty `then` branch }
      if errors = 'replace' then s := s + pychr_s(CP_REPLACEMENT)
      else if errors <> 'ignore' then
        raise UnicodeDecodeError.Create(
        'utf-8: invalid start byte or truncated sequence at position ' +
        IntToStr(i));
      i := i - L;   { L is negative: this ADVANCES past the maximal subpart }
    end;
  end;
  Utf8Decode_ := s;
end;

function NormaliseName(const name: AnsiString): AnsiString;
var i: Integer; c: Char; r: AnsiString;
begin
  { CPython lower-cases and folds spaces to underscores; the hyphen/underscore
    difference is what makes `utf-8` and `utf_8` the same codec, so fold both
    ways to one spelling here. }
  r := '';
  for i := 1 to Length(name) do
  begin
    c := name[i];
    if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    if (c = '_') or (c = ' ') then c := '-';
    r := r + c;
  end;
  NormaliseName := r;
end;

procedure AddCodec(const name: AnsiString; info: CodecInfo);
begin
  if RegCount >= Length(RegNames) then
  begin
    SetLength(RegNames, RegCount + 8);
    SetLength(RegInfos, RegCount + 8);
  end;
  RegNames[RegCount] := NormaliseName(name);
  RegInfos[RegCount] := info;
  Inc(RegCount);
end;

{ The seeded codecs. Each carries only what this subset can honour: the name,
  and the base classes as the incremental/stream slots so that a caller
  constructing one gets an object with an `errors` field rather than None. }
procedure Seed;
var ci: CodecInfo;
begin
  if Seeded then Exit;
  Seeded := True;

  ci := CodecInfo.Create(0, 0, 0, 0, 0, 0, 'utf-8');
  AddCodec('utf-8', ci);
  AddCodec('utf8', ci);
  AddCodec('u8', ci);

  ci := CodecInfo.Create(0, 0, 0, 0, 0, 0, 'ascii');
  AddCodec('ascii', ci);
  AddCodec('us-ascii', ci);
  AddCodec('646', ci);

  ci := CodecInfo.Create(0, 0, 0, 0, 0, 0, 'iso8859-1');
  AddCodec('iso8859-1', ci);
  AddCodec('latin-1', ci);
  AddCodec('latin1', ci);
  AddCodec('iso-8859-1', ci);
  AddCodec('8859', ci);
  AddCodec('cp819', ci);
end;

{ The built-in table only — nil when the name is not one of ours. Split out
  because `encode`/`decode` below need the CodecInfo as an OBJECT (they switch
  on its name), while the public `lookup` must be able to answer with whatever
  a search function handed back. }
function FindBuiltin(const norm: AnsiString): CodecInfo;
var i: Integer;
begin
  Seed;
  FindBuiltin := nil;
  for i := 0 to RegCount - 1 do
    if RegNames[i] = norm then
    begin
      FindBuiltin := RegInfos[i];
      Exit;
    end;
end;

function lookup(const name: AnsiString): Variant;
var i: Integer; norm: AnsiString; got: Variant; ci: CodecInfo;
begin
  norm := NormaliseName(name);
  ci := FindBuiltin(norm);
  if ci <> nil then
  begin
    lookup := ci;
    Exit;
  end;
  { registered search functions, newest last — a library installing its own
    codec is how x-user-defined arrives }
  for i := 0 to SearchCount - 1 do
  begin
    got := pybound_callv1(SearchFns[i], norm);
    if got <> pynone then
    begin
      lookup := got;
      Exit;
    end;
  end;
  raise LookupError.Create('unknown encoding: ' + name);
end;

procedure register(const search_function: Variant);
begin
  if SearchCount >= Length(SearchFns) then
    SetLength(SearchFns, SearchCount + 4);
  SearchFns[SearchCount] := search_function;
  Inc(SearchCount);
end;

{ `charmap_encode` answers a TUPLE, so element 0 arrives as a VARIANT that
  box-tags the TPyBytes -- not as the object. Unwrapping it needs `pyvarobj`;
  a hard cast `TPyBytes(v)` reinterprets the variant RECORD's own bytes as an
  object pointer and the result segfaults on first use.

  That cast was here, on both charmap arms, and it crashed `codecs.encode` for
  ascii and latin-1 on every input INCLUDING the empty string -- because the
  bad pointer is produced after the encode loop, not inside it, so having
  nothing to encode did not save it. utf-8 was unaffected: it returns
  `Utf8Encode_`'s TPyBytes directly and never goes through a tuple.

  The sibling `decode` never had the bug, and the asymmetry is what hid it: it
  assigns `r.at(0)` to an AnsiString RESULT, which is an ordinary variant
  conversion the compiler performs correctly. Only the object-typed arm needed
  an explicit unwrap, and only the object-typed arm got a cast instead.

  Named rather than inlined twice: two call sites that must agree is exactly
  how this drifted in the first place. `base64.pas:39` uses the same idiom. }
function BytesOfVar(const v: Variant): TPyBytes;
begin
  BytesOfVar := TPyBytes(pyvarobj(v));
end;

function encode(const input: AnsiString; const encoding: AnsiString;
                const errors: AnsiString): TPyBytes;
var norm: AnsiString; r: TPyList; ci: CodecInfo;
begin
  ci := FindBuiltin(NormaliseName(encoding));
  if ci = nil then raise LookupError.Create('unknown encoding: ' + encoding);
  norm := ci.name;
  if norm = 'utf-8' then encode := Utf8Encode_(input)
  else if norm = 'ascii' then
  begin
    r := charmap_encode(input, errors, charmap_build(AsciiTable));
    encode := BytesOfVar(r.at(0));
  end
  else
  begin
    r := charmap_encode(input, errors, charmap_build(Latin1Table));
    encode := BytesOfVar(r.at(0));
  end;
end;

function decode(input: TPyBytes; const encoding: AnsiString;
                const errors: AnsiString): AnsiString;
var norm: AnsiString; r: TPyList; ci: CodecInfo;
begin
  ci := FindBuiltin(NormaliseName(encoding));
  if ci = nil then raise LookupError.Create('unknown encoding: ' + encoding);
  norm := ci.name;
  if norm = 'utf-8' then decode := Utf8Decode_(input, errors)
  else if norm = 'ascii' then
  begin
    r := charmap_decode(input, errors, AsciiTable);
    decode := r.at(0);
  end
  else
  begin
    r := charmap_decode(input, errors, Latin1Table);
    decode := r.at(0);
  end;
end;

{ four bytes is the longest BOM, so one shape covers all five }
function Bom4(n, b0, b1, b2, b3: Integer): TPyBytes;
var r: TPyBytes;
begin
  r := TPyBytes.Create(n);
  r.put(0, b0);
  r.put(1, b1);
  if n > 2 then r.put(2, b2);
  if n > 3 then r.put(3, b3);
  Bom4 := r;
end;

begin
  RegCount := 0;
  SearchCount := 0;
  Seeded := False;
  BOM_UTF8     := Bom4(3, $EF, $BB, $BF, 0);
  BOM_UTF16_LE := Bom4(2, $FF, $FE, 0, 0);
  BOM_UTF16_BE := Bom4(2, $FE, $FF, 0, 0);
  BOM_UTF32_LE := Bom4(4, $FF, $FE, 0, 0);
  BOM_UTF32_BE := Bom4(4, 0, 0, $FE, $FF);
end.
