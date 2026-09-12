{ SPDX-License-Identifier: Zlib }
unit io;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `io` for the Nil-Python frontend — the in-memory buffers.

  Named `io` so `from io import BytesIO` needs no frontend change (NilPy maps
  `import X` onto the unit resolver; see devdocs/dev/python-compat-tiers.md).

  THE SUBSET:

    io.BytesIO([initial])  -> write / read / getvalue / seek / tell / close,
                              plus `.closed`
    io.StringIO([initial]) -> the same, over text
    io.open(path[, mode], encoding=..., errors=..., newline=...)
                           -> the file object the bare `open` builtin yields,
                              for a module that has rebound the bare name

  The two BUFFERS are what a program reaches for when a library wants a FILE
  and it has
  (or wants) bytes in memory — `img.save(buf, format="PNG")` then
  `buf.getvalue()`. NOT here: TextIOWrapper, BufferedReader, and the encoding
  machinery — `io.open` is here, but only as the bare builtin's own file object
  under a second name, so it inherits that object's limits rather than lifting
  them (this line said `io.open` was absent until 2026-09-12).

  Bytes are held as an AnsiString, which in this dialect is a length-carrying
  byte string, so a NUL is data like any other byte. }

interface

uses pylib;

type
  BytesIO = class
  public
    buf: AnsiString;
    pos: Integer;                  { 0-based, as Python's tell() reports }
    closed: Boolean;
    { `BytesIO()` or `BytesIO(data)` — the initial contents, positioned at 0. }
    constructor Create(const initial: Variant = 0);
    { Append at the current position and advance it; returns the count written,
      as Python's does. }
    function write(const data: Variant): Integer;
    { The whole buffer regardless of position, which is what getvalue means. }
    function getvalue: AnsiString;
    { `read()` = the rest; `read(n)` = at most n bytes. }
    function read(n: Integer = -1): AnsiString;
    function seek(offset: Integer; whence: Integer = 0): Integer;
    function tell: Integer;
    procedure close;
  end;

  StringIO = class(BytesIO)
  end;

{ `io.open` — THE SAME OBJECT the bare `open` builtin already yields, reached
  through the module name. A module that defines its own `open` (lekkerzeilen's
  world.py does, for scenes) must write `io.open` to get the file one, and that
  spelling had no member at all: `import io` binds THIS unit, so the lookup
  found a unit without an `open` and said "no member open came of the qualifier
  io" — a diagnostic whose own hint ("an import that bound nothing") points at
  the wrong cause, because the import bound fine.

  Because it returns the builtin's own TPyFile, EVERY divergence from CPython
  that bare `open` has, this has — including no newline translation, which is
  the one a text-mode reader can actually hit. Nothing here claims more than
  `open` does.

  The keywords are DECLARED rather than skipped. The bare builtin's lowering
  discards trailing arguments, so `open(p, encoding="utf-8")` dies on
  `undefined variable (encoding)` — the second argument is parsed as the MODE
  and the skip loop only starts at the third. A Pascal parameter of that name
  binds it instead (PyKwArgIndex), and the default `= 0` is VT_EMPTY, which is
  also what `None` is (pynone), so one `pyvartag = 0` test means "absent or
  None" and there is no third state to get wrong.

  An encoding, `errors` or `newline` we would have to IGNORE is REFUSED, not
  accepted: our strings are byte strings, so utf-8 and latin-1 are the identity
  and anything else would hand the caller a plausible wrong string. Extend the
  accepted list when a program actually wants one. }
function open(const path: AnsiString; const mode: AnsiString = 'r';
              const buffering: Variant = 0;
              const encoding: Variant = 0;
              const errors: Variant = 0;
              const newline: Variant = 0): TPyFile;

implementation

constructor BytesIO.Create(const initial: Variant);
begin
  if pyvartag(initial) = 0 then buf := '' else buf := pystr_of(initial);
  pos := 0;
  closed := False;
end;

function BytesIO.write(const data: Variant): Integer;
var s: AnsiString;
begin
  s := pystr_of(data);
  { A write past the end extends the buffer; a write in the middle overwrites,
    which is what a seek-then-write means. }
  if pos = Length(buf) then
    buf := buf + s
  else
  begin
    while Length(buf) < pos do buf := buf + #0;
    buf := Copy(buf, 1, pos) + s + Copy(buf, pos + Length(s) + 1, Length(buf));
  end;
  pos := pos + Length(s);
  Result := Length(s);
end;

function BytesIO.getvalue: AnsiString;
begin
  Result := buf;
end;

function BytesIO.read(n: Integer): AnsiString;
var take: Integer;
begin
  take := Length(buf) - pos;
  if (n >= 0) and (n < take) then take := n;
  if take <= 0 then begin Result := ''; Exit; end;
  Result := Copy(buf, pos + 1, take);
  pos := pos + take;
end;

function BytesIO.seek(offset, whence: Integer): Integer;
begin
  case whence of
    1: pos := pos + offset;             { SEEK_CUR }
    2: pos := Length(buf) + offset;     { SEEK_END }
  else
    pos := offset;                      { SEEK_SET }
  end;
  if pos < 0 then pos := 0;
  Result := pos;
end;

function BytesIO.tell: Integer;
begin
  Result := pos;
end;

procedure BytesIO.close;
begin
  closed := True;
end;

{ Fold an encoding name the way Python's codec lookup does — case and the
  `-`/`_` spelling are not significant, so `UTF_8` and `utf-8` are one name. }
function IoFoldEnc(const s: AnsiString): AnsiString;
var i: Integer; c: Char;
begin
  Result := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    if c = '_' then c := '-';
    Result := Result + c;
  end;
end;

function open(const path: AnsiString; const mode: AnsiString;
              const buffering: Variant;
              const encoding: Variant;
              const errors: Variant;
              const newline: Variant): TPyFile;
var enc, err, nl: AnsiString;
begin
  { buffering is a performance hint with no observable consequence here, so it
    is accepted and dropped. Note that `buffering=0` is indistinguishable from
    absent — both are VT_EMPTY — which costs nothing only BECAUSE it is
    dropped; a future semantic use of it would need a different sentinel. }
  if pyvartag(encoding) <> 0 then
  begin
    enc := IoFoldEnc(pystr_of(encoding));
    { The byte-identical set for a byte-string model: utf-8 and the 8-bit
      single-byte families. utf-16/32 and the codepages are a real decode and
      would return a wrong string rather than fail. }
    if (enc <> 'utf-8') and (enc <> 'utf8') and
       (enc <> 'ascii') and (enc <> 'us-ascii') and
       (enc <> 'latin-1') and (enc <> 'latin1') and (enc <> 'iso-8859-1') then
      raise ValueError.Create('io.open: encoding ' + enc +
        ' would need a real decode — this unit reads bytes, so it would ' +
        'return a wrong string rather than fail (utf-8, ascii and latin-1 ' +
        'are the identity here and are accepted)');
  end;
  if pyvartag(errors) <> 0 then
  begin
    err := IoFoldEnc(pystr_of(errors));
    { We never decode, so we never produce a decode error to handle. `strict`
      asks for the behaviour we have; `replace`/`ignore` ask us to alter bytes
      we would otherwise keep, and silently not doing it is the wrong value. }
    if err <> 'strict' then
      raise ValueError.Create('io.open: errors=' + err +
        ' asks for bytes to be altered on a decode this unit does not do ' +
        '(only strict is accepted)');
  end;
  if pyvartag(newline) <> 0 then
  begin
    { Escaped, not raw: the value IS a line ending, so interpolating it splits
      the diagnostic across lines and the second half reads as a stray message. }
    nl := pystr_of(newline);
    nl := pystr_replace(nl, #13, '\r');
    nl := pystr_replace(nl, #10, '\n');
    { '' means "recognise every line ending, translate none", which is what we
      do. An explicit '\n' / '\r' / '\r\n' asks for translation we do not do. }
    if nl <> '' then
      raise ValueError.Create('io.open: newline=' + nl +
        ' asks for line-ending translation this unit does not do (absent, ' +
        'None and '''' are accepted; all three read the bytes through)');
  end;
  Result := pyfile_open(path, mode);
end;

end.
