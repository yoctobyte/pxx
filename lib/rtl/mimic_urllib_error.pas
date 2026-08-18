{ SPDX-License-Identifier: Zlib }
unit mimic_urllib_error;
{ Python's `urllib.error` — the exceptions `urllib.request` raises.

  `import urllib.error` / `from urllib.error import HTTPError` RESOLVES here
  through the NilPy import resolver's `mimic_` fallback, so no file in the tree
  carries the stdlib's name and `--no-shims` can turn the substitution into an
  error. See devdocs/dev/python-compat-tiers.md.

  WHY A SEPARATE UNIT, and why the classes live HERE rather than in
  mimic_urllib_request: CPython declares them in `urllib.error` and RE-EXPORTS
  them from `urllib.request`, and a caller writes either spelling. Declaring
  them twice would make `except HTTPError` miss an error raised through the
  other name — same class identity is the whole point, so there is one
  declaration and mimic_urllib_request aliases it.

  THE SUBSET: `URLError`, `HTTPError`, `ContentTooShortError` — CPython's whole
  `urllib.error` surface, so this one is complete rather than a subset.

  `__str__` is spelled out on both classes because CPython's wording is part of
  the interface: code that logs `str(e)` prints `HTTP Error 404: Not Found`,
  not a repr.

  TWO HAZARDS AROUND THAT, both measured, because they look identical from the
  NilPy side and the obvious diagnosis is the wrong one:

  1. URLError descends from `OSError` and NOT from a bare `Exception`. That is
     load-bearing beyond matching CPython's ancestry. `uses pylib, sysutils`
     makes a bare `Exception` resolve to SYSUTILS' Exception — pylib's is a
     deliberate sibling, not the same class (see pylib.pas's header) — so
     `class(Exception)` here would land in the wrong tree and NilPy would not
     stringify it as a Python exception at all. `OSError` is declared only by
     pylib, so naming it cannot pick the wrong tree.
  2. `str(e)` currently dispatches `__str__` by the STATIC type of the except
     clause, so `except URLError` sees these methods and `except Exception`
     does not — see
     bug-n-str-of-a-pascal-declared-exception-ignores-str-when-caught-as-a-base.
     That bug is NOT why these methods exist; they would be here for CPython
     parity regardless, and they are what makes the common arm right today. }

interface

uses pylib, sysutils;

type
  { `urllib.error.URLError(reason)` — a transport-level failure: the name did
    not resolve, the connection was refused, the scheme is not one we speak.
    CPython descends it from OSError, and code in the wild writes
    `except OSError` around urlopen, so the ancestry is load-bearing. }
  URLError = class(OSError)
  public
    reason: AnsiString;
    { CPython sets .filename only when the opener knows one; it is here so an
      `e.filename` read does not fail on a class that CPython gives one. }
    filename: AnsiString;
    constructor Create(const reason: AnsiString);
    function __str__: AnsiString;
  end;

  { `urllib.error.HTTPError(url, code, msg, hdrs, fp)` — a response that ARRIVED
    and carried a status the opener treats as an error (CPython: anything
    outside 2xx once redirects are followed).

    It is BOTH an exception and a response, which is not a quirk to tidy away:
    a caller reads `e.code` and then `e.read()` for the error body, and an
    HTTPError that dropped the body would silently lose the half of the answer
    that says what went wrong. So the body is carried. }
  HTTPError = class(URLError)
  public
    code: Integer;
    { CPython 3.9+ spells the same number `.status` too, and new code uses it. }
    status: Integer;
    msg: AnsiString;
    url: AnsiString;
    { the response headers, as the same HTTPMessage-shaped object a successful
      urlopen answers with — a Variant because that class lives in
      mimic_urllib_request, which uses THIS unit and so cannot be used by it. }
    headers: Variant;
    body: AnsiString;
    constructor Create(const url: AnsiString; code: Integer;
                       const msg: AnsiString; const hdrs: Variant = 0;
                       const body: AnsiString = '');
    function __str__: AnsiString;
    { the response face: CPython's HTTPError answers these because it IS one }
    function read(n: Integer = -1): TPyBytes;
    function geturl: AnsiString;
    function getcode: Integer;
    function info: Variant;
    procedure close;
    function __enter__: HTTPError;
    procedure __exit__(const a: Variant = 0; const b: Variant = 0;
                       const c: Variant = 0);
  end;

  { `urllib.error.ContentTooShortError(message, content)` — urlretrieve got
    fewer bytes than the Content-Length promised. }
  ContentTooShortError = class(URLError)
  public
    content: AnsiString;
    constructor Create(const message: AnsiString; const content: AnsiString = '');
    { NO __str__ override: CPython inherits URLError's, so
      `str(ContentTooShortError('short read'))` is `<urlopen error short read>`.
      Checked against CPython rather than guessed — the first draft here gave it
      the plain message, which is what it looks like it should do and is wrong. }
  end;

implementation

constructor URLError.Create(const reason: AnsiString);
begin
  { the base carries `msg`, which is what a bare `except Exception as e` reads }
  inherited Create(reason);
  Self.reason := reason;
  Self.filename := '';
end;

function URLError.__str__: AnsiString;
begin
  { CPython: '<urlopen error %s>' % self.reason — the angle brackets are part
    of it and appear in real logs, so they are not decoration to drop. }
  __str__ := '<urlopen error ' + reason + '>';
end;

constructor HTTPError.Create(const url: AnsiString; code: Integer;
                             const msg: AnsiString; const hdrs: Variant;
                             const body: AnsiString);
begin
  { CPython's HTTPError sets .reason to msg, not to a transport reason. }
  inherited Create(msg);
  Self.url := url;
  Self.filename := url;
  Self.code := code;
  Self.status := code;
  Self.msg := msg;
  Self.headers := hdrs;
  Self.body := body;
end;

function HTTPError.__str__: AnsiString;
begin
  { CPython: 'HTTP Error %s: %s' % (self.code, self.msg) }
  __str__ := 'HTTP Error ' + IntToStr(code) + ': ' + msg;
end;

function HTTPError.read(n: Integer): TPyBytes;
var i, take: Integer; r: TPyBytes;
begin
  take := Length(body);
  if (n >= 0) and (n < take) then take := n;
  r := TPyBytes.Create(take);
  for i := 1 to take do r.put(i - 1, Ord(body[i]));
  read := r;
end;

function HTTPError.geturl: AnsiString;
begin
  geturl := url;
end;

function HTTPError.getcode: Integer;
begin
  getcode := code;
end;

function HTTPError.info: Variant;
begin
  info := headers;
end;

procedure HTTPError.close;
begin
  { the body is already in hand — there is no socket left to release }
end;

function HTTPError.__enter__: HTTPError;
begin
  __enter__ := Self;
end;

procedure HTTPError.__exit__(const a, b, c: Variant);
begin
end;

constructor ContentTooShortError.Create(const message: AnsiString;
                                        const content: AnsiString);
begin
  inherited Create(message);
  Self.content := content;
end;

end.
