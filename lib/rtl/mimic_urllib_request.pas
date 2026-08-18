{ SPDX-License-Identifier: Zlib }
unit mimic_urllib_request;
{ Python's `urllib.request`, over this RTL's own HTTP client (lib/rtl/http.pas).

  `from urllib.request import urlopen` RESOLVES here through the NilPy import
  resolver's `mimic_` fallback, so no file in the tree carries the stdlib's
  name and `--no-shims` can turn the substitution into an error. See
  devdocs/dev/python-compat-tiers.md.

  This REPLACES the earlier mimic_urllib_request.py, which existed only so that
  importing code compiled and raised NotImplementedError on every call. It is a
  `.pas` and not a `.py` for one measured reason: http.pas answers with RECORDS
  (THttpResponse), which is a Pascal-side shape, and the shim's whole job is to
  turn one into a Python object. `uses http` needs no -Fu (measured), so the
  swap costs a caller nothing. Shape precedent: mimic_codecs.pas.

  THE SUBSET, stated plainly — what works:
    urlopen(url_or_Request, data=None, timeout=<default>) over http:// and,
    with a TLS backend registered, https://; redirects followed; the response
    object with read/readline/readlines/status/code/reason/url/headers/info/
    geturl/getcode/close and `with` support; Request with method, headers, data;
    urlretrieve to a file; quote/unquote/urlencode reachable through
    urllib.parse, which is a different shim (mimic_urllib_parse).

  WHAT IT REFUSES, LOUDLY, and why each one refuses rather than approximates:
    * a non-default `timeout`. http.pas has NO timeout parameter at all
      (measured: no occurrence of the word in the unit). Accepting the argument
      and ignoring it would turn "give up after 2 seconds" into "block
      forever", which is the failure class this project treats as worst — the
      caller asked for a bound and would silently not get one.
    * https:// with no TLS backend registered. http.pas ships two and
      deliberately registers NEITHER — the caller picks (tls13_native or
      tls_openssl). So the refusal names them instead of choosing one here: a
      shim picking a TLS policy for the program is exactly the kind of quiet
      decision that should not live in a compatibility layer.
    * any scheme other than http/https — ftp://, file://, data://. CPython's
      opener handles several; this one speaks HTTP.
    * the opener/handler machinery: build_opener, install_opener,
      HTTPBasicAuthHandler, ProxyHandler, Request.set_proxy. These are absent
      rather than stubbed, so `build_opener` is a COMPILE error naming the
      missing name (measured: `undefined variable (build_opener)`) instead of
      an object that quietly ignores the handlers it was given.
      Basic auth is still reachable: put the header on the Request yourself
      (http.pas's HttpBasicAuth builds it).

  MEASURED AGAINST CPython, not guessed at. test/lib_mimic_urllib_request.npy
  runs TWICE under `make lib-test` — once under python3, once compiled here —
  against the SAME local server (test/lib_mimic_urllib_request_server.pas), and
  the two outputs are diffed. Pointing both clients at one server is what makes
  it a comparison against the real urllib rather than against our own idea of
  what a server says. The refusals above have no oracle by construction (CPython
  does those things rather than refusing) and are checked separately, for the
  SHAPE of the refusal, in test/lib_mimic_urllib_request_refusals.npy.

  Several lines in this unit are the way they are because the oracle disagreed
  with the obvious guess — the removed get_type()/get_host()/get_selector()
  methods, `origin_req_host` dropping the port, `has_header` not folding the
  name, ContentTooShortError's inherited str. Each is noted where it happens.

  feature-b-mimic-urllib-request-over-the-rtl-http-stack }

interface

uses pylib, sysutils, http, tls, platform, mimic_urllib_error;

const
  { The sentinel for "the caller passed no timeout". CPython's default is the
    module-level socket default, which is None = block forever — and blocking
    forever is precisely what http.pas does, so the DEFAULT is honest and only
    an explicit timeout has to refuse. -1 rather than 0 because `timeout=0` is a
    real (if hostile) CPython request meaning "non-blocking", which we also
    cannot honour and which must therefore reach the refusal. }
  TIMEOUT_DEFAULT = -1;

type
  { `http.client.HTTPMessage` — what `response.headers` / `response.info()`
    answers. CPython's is an email.message.Message; the part every urlopen
    caller uses is case-insensitive lookup plus iteration, so that is what is
    here, over the raw header block http.pas already parsed.

    NOT a dict: HTTP allows a header to repeat (Set-Cookie above all), and a
    dict would silently keep one. `get_all` is the CPython name for reading
    them all back, and it is here for that reason. }
  HTTPMessage = class
  public
    { the raw header block, exactly as it came off the wire (no status line) }
    raw: AnsiString;
    constructor Create(const raw: AnsiString);
    { `msg.get(name[, failobj])` — first match, case-insensitive. CPython
      answers None when absent and that is what the one-argument form does. }
    function get(const name: AnsiString): Variant; overload;
    function get(const name: AnsiString; const failobj: Variant): Variant; overload;
    { `msg['Name']` — CPython's __getitem__ IS get(), None and all. }
    function fetch(const name: AnsiString): Variant;
    { `msg.get_all(name)` — every value for the name, in wire order; CPython
      answers None (not []) when the header is absent, which callers test. }
    function get_all(const name: AnsiString): Variant;
    { `name in msg` }
    function has_key(const name: AnsiString): Boolean;
    { `msg.keys()` / `msg.values()` / `msg.items()` — repeats included, in
      order, exactly as CPython's Message does. }
    function keylist: TPyList;
    function vallist: TPyList;
    function itemlist: TPyList;
    { `msg.get_content_type()` — the Content-Type minus any parameters. }
    function get_content_type: AnsiString;
    { `str(msg)` is the header block itself, which is what CPython prints. }
    function __str__: AnsiString;
    property Items[const name: AnsiString]: Variant read fetch; default;
  end;

  { What `urlopen` answers on success — CPython's http.client.HTTPResponse as
    seen through urlopen (an addinfourl in older versions).

    The body is ALREADY IN HAND when this is built, because http.pas reads a
    whole response before it parses one. So `read()` here is a cursor over a
    string rather than a socket read, and that is a real difference from
    CPython worth knowing: a huge download is fully buffered, and `read(8192)`
    in a loop does not stream. It is stated rather than hidden because a caller
    streaming a 2 GB file needs to know before, not after. }
  HTTPResponse = class
  public
    { CPython spells the status three ways and code in the wild uses all of
      them: `.status` (3.9+), `.code` (legacy), `.getcode()`. One number. }
    status: Integer;
    code: Integer;
    reason: AnsiString;
    { the FINAL url — after redirects, which is why a caller reads it }
    url: AnsiString;
    headers: HTTPMessage;
    { the whole body, and the read cursor over it (0-based, in bytes) }
    body: AnsiString;
    pos: Integer;
    constructor Create(const url: AnsiString; status: Integer;
                       const reason, headerBlock, body: AnsiString);
    { `read()` / `read(n)` — bytes, as CPython's does. n<0 or omitted is "the
      rest"; at EOF it answers b'' rather than raising, like CPython. }
    function read(n: Integer = -1): TPyBytes;
    { `readline()` — up to and INCLUDING the newline, b'' at EOF. }
    function readline: TPyBytes;
    function readlines: TPyList;
    { `resp.info()` / `resp.geturl()` / `resp.getcode()` — the addinfourl trio,
      still what a lot of code calls. }
    function info: HTTPMessage;
    function geturl: AnsiString;
    function getcode: Integer;
    { `resp.getheader(name[, default])` — http.client's spelling. }
    function getheader(const name: AnsiString): Variant; overload;
    function getheader(const name: AnsiString; const default_: Variant): Variant; overload;
    function getheaders: TPyList;
    procedure close;
    function closed: Boolean;
    { `with urlopen(...) as r:` — measured to work over this seam. }
    function __enter__: HTTPResponse;
    procedure __exit__(const a: Variant = 0; const b: Variant = 0;
                       const c: Variant = 0);
  end;

  { `urllib.request.Request(url, data=None, headers={}, method=None)`.

    Constructing one is side-effect free — it holds what it was handed — so
    this class was already real in the refusing .py shim that preceded this
    unit, and its behaviour is unchanged here. }
  Request = class
  public
    full_url: AnsiString;
    { bytes or None; a Variant because it is a Python value either way }
    data: Variant;
    headers: TPyDict;
    { the explicit method, or '' for CPython's "POST if data else GET" }
    method: AnsiString;
    constructor Create(const url: AnsiString; const data: Variant = 0;
                       const headers: Variant = 0;
                       const method: AnsiString = '');
    function get_full_url: AnsiString;
    { CPython: the explicit method, else POST when there is data, else GET. }
    function get_method: AnsiString;
    { CPython CAPITALISES the header name on the way in (`Content-type`), and a
      caller that adds 'CONTENT-TYPE' then reads `.headers['Content-type']`
      depends on it, so the folding is reproduced rather than tidied. }
    procedure add_header(const key, val: AnsiString);
    procedure add_unredirected_header(const key, val: AnsiString);
    function has_header(const key: AnsiString): Boolean;
    function get_header(const key: AnsiString): Variant; overload;
    function get_header(const key: AnsiString; const default_: Variant): Variant; overload;
    function header_items: TPyList;
    procedure remove_header(const key: AnsiString);
    { The url pieces, as ATTRIBUTES — which is what CPython has. It used to
      spell them get_type()/get_host()/get_selector() and those methods are
      GONE from current CPython, so writing them here would have added a
      surface the oracle does not have while missing the one it does. Measured,
      not remembered: the first draft of this class had the methods.

      `selector` excludes any #fragment (CPython puts it in `fragment`, which
      is None when there is none) and is '' — not '/' — for a bare host, which
      is CPython's answer and differs from http.pas's path default. }
    host: AnsiString;
    { `&type` — the escaped spelling, because Python's attribute is called
      `type` and Pascal reserves the word. A field named `type_` compiled fine
      and was NOT reachable as `r.type` from NilPy: the frontend's
      trailing-underscore fallback covers METHODS, not attributes (measured).
      Escaping keeps the Python name, which is the one that has to be right. }
    &type: AnsiString;
    selector: AnsiString;
    fragment: Variant;
    { CPython's cookie-policy fields. Present with their default values because
      code reads them; this shim has no cookie processor to act on them. }
    origin_req_host: AnsiString;
    unverifiable: Boolean;
  end;

{ ---- the module functions ------------------------------------------------ }

{ `urlopen(url, data=None, timeout=...)`. `url` is a str or a Request.

  Raises HTTPError when a response arrives with a status outside 2xx (after
  redirects), URLError when no response arrives at all — which is CPython's
  split and the reason a caller catches them separately. }
function urlopen(const url: Variant; const data: Variant = 0;
                 timeout: Integer = TIMEOUT_DEFAULT): HTTPResponse;

{ `urlretrieve(url, filename=None)` -> `(filename, headers)`.

  A filename is REQUIRED here, unlike CPython, which invents a temporary file
  when none is given. Inventing one needs a tempfile policy (where, what
  permissions, who cleans it up) that a compatibility shim should not be
  choosing on the program's behalf, so the one-argument form refuses and says
  so rather than writing somewhere the caller did not ask for. }
function urlretrieve(const url: Variant): TPyList; overload;
function urlretrieve(const url: Variant; const filename: AnsiString): TPyList; overload;

{ Re-exports of the mimic_urllib_error classes. CPython's `urllib.request`
  namespace carries these names too (`urllib.request.HTTPError` is the same
  object as `urllib.error.HTTPError`), and code catches them off either module.
  ALIASES, not new declarations — one class identity, so an `except HTTPError:`
  written against either import catches what this unit raises. }
type
  URLError = mimic_urllib_error.URLError;
  HTTPError = mimic_urllib_error.HTTPError;
  ContentTooShortError = mimic_urllib_error.ContentTooShortError;

implementation

{ ---- HTTPMessage --------------------------------------------------------- }

constructor HTTPMessage.Create(const raw: AnsiString);
begin
  Self.raw := raw;
end;

{ ONE header lookup, as a free function the three entry points below delegate
  to — `get`, `get(name, failobj)` and `__getitem__` are three CPython spellings
  of a single question, and giving each its own walk is how the second one stays
  broken (devdocs/dev/normalise-dont-special-case.md). }
function HeaderFirst(const raw, name: AnsiString; const failobj: Variant): Variant;
var h: THttpHeaders; i: Integer;
begin
  h := HttpParseHeaders(raw);
  for i := 0 to h.Count - 1 do
    if LowerCase(HttpHeaderName(h, i)) = LowerCase(name) then
    begin
      HeaderFirst := HttpHeaderVal(h, i);
      Exit;
    end;
  HeaderFirst := failobj;
end;

function HTTPMessage.get(const name: AnsiString): Variant;
begin
  get := HeaderFirst(raw, name, pynone);
end;

function HTTPMessage.get(const name: AnsiString; const failobj: Variant): Variant;
begin
  get := HeaderFirst(raw, name, failobj);
end;

function HTTPMessage.fetch(const name: AnsiString): Variant;
begin
  { CPython's Message.__getitem__ IS get() — None for an absent header, not a
    KeyError. That is a real difference from dict and callers rely on it. }
  fetch := HeaderFirst(raw, name, pynone);
end;

function HTTPMessage.get_all(const name: AnsiString): Variant;
var h: THttpHeaders; i: Integer; l: TPyList;
begin
  h := HttpParseHeaders(raw);
  l := TPyList.Create;
  for i := 0 to h.Count - 1 do
    if LowerCase(HttpHeaderName(h, i)) = LowerCase(name) then
      l.append(HttpHeaderVal(h, i));
  { CPython answers None, not an empty list, for a header that is not there —
    and `if msg.get_all('set-cookie') is None` is how callers test it. }
  if l.count = 0 then get_all := pynone else get_all := l;
end;

function HTTPMessage.has_key(const name: AnsiString): Boolean;
var h: THttpHeaders;
begin
  h := HttpParseHeaders(raw);
  has_key := HttpHeadersHas(h, name);
end;

function HTTPMessage.keylist: TPyList;
var h: THttpHeaders; i: Integer; l: TPyList;
begin
  h := HttpParseHeaders(raw);
  l := TPyList.Create;
  for i := 0 to h.Count - 1 do l.append(HttpHeaderName(h, i));
  keylist := l;
end;

function HTTPMessage.vallist: TPyList;
var h: THttpHeaders; i: Integer; l: TPyList;
begin
  h := HttpParseHeaders(raw);
  l := TPyList.Create;
  for i := 0 to h.Count - 1 do l.append(HttpHeaderVal(h, i));
  vallist := l;
end;

function HTTPMessage.itemlist: TPyList;
var h: THttpHeaders; i: Integer; l, pair: TPyList;
begin
  h := HttpParseHeaders(raw);
  l := TPyList.Create;
  for i := 0 to h.Count - 1 do
  begin
    pair := TPyList.Create;
    pair.append(HttpHeaderName(h, i));
    pair.append(HttpHeaderVal(h, i));
    l.append(tuple(pair));
  end;
  itemlist := l;
end;

function HTTPMessage.get_content_type: AnsiString;
var v: AnsiString; i: Integer;
begin
  v := HttpHeaderValue(raw, 'Content-Type');
  { strip any '; charset=...' parameters, which is what CPython's
    get_content_type does — and lower-case it, which it also does. }
  i := 1;
  while (i <= Length(v)) and (v[i] <> ';') do Inc(i);
  v := Trim(Copy(v, 1, i - 1));
  { CPython falls back to text/plain when there is no Content-Type at all. }
  if v = '' then v := 'text/plain';
  get_content_type := LowerCase(v);
end;

function HTTPMessage.__str__: AnsiString;
begin
  __str__ := raw;
end;

{ ---- HTTPResponse -------------------------------------------------------- }

constructor HTTPResponse.Create(const url: AnsiString; status: Integer;
                                const reason, headerBlock, body: AnsiString);
begin
  Self.url := url;
  Self.status := status;
  Self.code := status;
  Self.reason := reason;
  Self.headers := HTTPMessage.Create(headerBlock);
  Self.body := body;
  Self.pos := 0;
end;

function HTTPResponse.read(n: Integer): TPyBytes;
var take, i: Integer; r: TPyBytes;
begin
  take := Length(body) - pos;
  if take < 0 then take := 0;
  if (n >= 0) and (n < take) then take := n;
  r := TPyBytes.Create(take);
  for i := 0 to take - 1 do r.put(i, Ord(body[pos + i + 1]));
  pos := pos + take;
  read := r;
end;

function HTTPResponse.readline: TPyBytes;
var i, take: Integer; r: TPyBytes;
begin
  i := pos;
  while (i < Length(body)) and (body[i + 1] <> #10) do Inc(i);
  { include the newline itself when there is one — CPython's readline does }
  if i < Length(body) then Inc(i);
  take := i - pos;
  r := TPyBytes.Create(take);
  for i := 0 to take - 1 do r.put(i, Ord(body[pos + i + 1]));
  pos := pos + take;
  readline := r;
end;

function HTTPResponse.readlines: TPyList;
var l: TPyList; b: TPyBytes;
begin
  l := TPyList.Create;
  b := readline;
  while b.count > 0 do
  begin
    l.append(b);
    b := readline;
  end;
  readlines := l;
end;

function HTTPResponse.info: HTTPMessage;
begin
  info := headers;
end;

function HTTPResponse.geturl: AnsiString;
begin
  geturl := url;
end;

function HTTPResponse.getcode: Integer;
begin
  getcode := status;
end;

function HTTPResponse.getheader(const name: AnsiString): Variant;
begin
  getheader := headers.get(name);
end;

function HTTPResponse.getheader(const name: AnsiString;
                                const default_: Variant): Variant;
begin
  getheader := headers.get(name, default_);
end;

function HTTPResponse.getheaders: TPyList;
begin
  getheaders := headers.itemlist;
end;

procedure HTTPResponse.close;
begin
  { The connection is already closed — http.pas read the whole response before
    handing it over. Park the cursor at EOF so a read after close answers b'',
    which is what a closed CPython response does for the common case. }
  pos := Length(body);
end;

function HTTPResponse.closed: Boolean;
begin
  closed := pos >= Length(body);
end;

function HTTPResponse.__enter__: HTTPResponse;
begin
  __enter__ := Self;
end;

procedure HTTPResponse.__exit__(const a, b, c: Variant);
begin
  close;
end;

{ ---- Request ------------------------------------------------------------- }

{ An omitted `Variant` argument arrives as the INTEGER 0, not as None — a
  Pascal default value has to be a constant and `pynone` is a function, so 0 is
  the only sentinel available. Measured, and it matters: `v = pynone` is FALSE
  for an omitted argument, so testing against None alone reads "omitted" as
  "the caller passed something". That is what made `urlopen(req)` overwrite the
  Request's own data with 0 and POST the body `0` — a wrong VALUE that reached
  the server and came back looking plausible, which is exactly the failure class
  the debugging playbook warns is expensive.

  Normalising here, once, at every entry point means the rest of the unit only
  ever sees None-or-real and no second sentinel test can drift out of step
  (devdocs/dev/normalise-dont-special-case.md). Treating an integer 0 as
  "omitted" is safe for `data`: CPython requires bytes there and raises TypeError
  on an int, so no working CPython program can be passing one. }
function ArgOrNone(const v: Variant): Variant;
begin
  if pyvar_is_inttag(v) and (pystr_of(v) = '0') then ArgOrNone := pynone
  else ArgOrNone := v;
end;

{ CPython's Request.add_header runs the name through `.capitalize()`, so
  'CONTENT-TYPE' is stored as 'Content-type'. Reproduced because a caller that
  adds one spelling and reads another depends on the fold. }
function CapitalizeHeader(const name: AnsiString): AnsiString;
var i: Integer; r: AnsiString; c: Char;
begin
  r := '';
  for i := 1 to Length(name) do
  begin
    c := name[i];
    if i = 1 then
    begin
      if (c >= 'a') and (c <= 'z') then c := Chr(Ord(c) - 32);
    end
    else
      if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    r := r + c;
  end;
  CapitalizeHeader := r;
end;

{ The url pieces, through http.pas's own splitter so there is ONE url grammar
  in play rather than a second one written here — the sibling-path trap in
  devdocs/dev/normalise-dont-special-case.md. Only the two places CPython
  differs from HttpParseUrl are adjusted, and both are noted where they happen. }
{ 'example.com:8080' -> 'example.com'. }
function HostWithoutPort(const h: AnsiString): AnsiString;
var i: Integer;
begin
  i := 1;
  while (i <= Length(h)) and (h[i] <> ':') do Inc(i);
  HostWithoutPort := Copy(h, 1, i - 1);
end;

procedure SplitUrlParts(const url: AnsiString;
                        var scheme, host, selector: AnsiString;
                        var fragment: Variant);
var h, p, bare: AnsiString; port, i: Integer; tls_: Boolean;
begin
  scheme := ''; host := ''; selector := ''; fragment := pynone;

  { the #fragment comes off first — CPython keeps it out of the selector }
  bare := url;
  i := 1;
  while (i <= Length(bare)) and (bare[i] <> '#') do Inc(i);
  if i <= Length(bare) then
  begin
    fragment := Copy(bare, i + 1, Length(bare));
    bare := Copy(bare, 1, i - 1);
  end;

  if not HttpParseUrl(bare, h, port, p, tls_) then Exit;

  if tls_ then scheme := 'https' else scheme := 'http';

  { CPython keeps an explicit :port on .host and omits a default one. }
  if ((not tls_) and (port <> 80)) or (tls_ and (port <> 443)) then
    host := h + ':' + IntToStr(port)
  else
    host := h;

  { HttpParseUrl defaults an empty path to '/', because that is what goes on
    the wire. CPython's .selector reports '' for a bare host — the url as
    WRITTEN, not as requested. Both are right for their own question, so the
    difference is converted here rather than changed in http.pas, where it
    would be wrong for every other caller. }
  selector := p;
  if (selector = '/') and (Pos('/', Copy(bare, 9, Length(bare))) = 0) then
    selector := '';
end;

constructor Request.Create(const url: AnsiString; const data: Variant;
                           const headers: Variant; const method: AnsiString);
var k: Variant; i: Integer; src: TPyDict; keys: TPyList;
begin
  Self.full_url := url;
  Self.data := ArgOrNone(data);
  Self.method := method;
  Self.headers := TPyDict.Create;
  SplitUrlParts(url, Self.&type, Self.host, Self.selector, Self.fragment);
  { CPython's origin_req_host is request_host(), which drops the :port — not
    .host, which keeps it. Measured against the oracle; they differ. }
  Self.origin_req_host := HostWithoutPort(Self.host);
  Self.unverifiable := False;
  { A headers dict handed in is copied through add_header, so the CPython
    capitalisation applies to it too — CPython does exactly this in __init__. }
  if pyvar_is_objtag(headers) then
  begin
    src := nil;
    if TObject(pyvarobj(headers)) is TPyDict then
      src := TPyDict(pyvarobj(headers));
    if src <> nil then
    begin
      keys := src.keylist;
      for i := 0 to keys.count - 1 do
      begin
        k := keys.at(i);
        Self.headers.store(CapitalizeHeader(pystr_of(k)), src.fetch(k));
      end;
    end;
  end;
end;

function Request.get_full_url: AnsiString;
begin
  get_full_url := full_url;
end;

function Request.get_method: AnsiString;
begin
  if method <> '' then get_method := method
  else if data = pynone then get_method := 'GET'
  else get_method := 'POST';
end;

procedure Request.add_header(const key, val: AnsiString);
begin
  headers.store(CapitalizeHeader(key), val);
end;

procedure Request.add_unredirected_header(const key, val: AnsiString);
begin
  { CPython keeps these in a SEPARATE dict that is dropped when a redirect is
    followed. This shim keeps one dict, so the header survives a hop it would
    not survive in CPython. Stated rather than silently differing: it matters
    only for a header you must not leak to another host (an Authorization),
    and a caller doing that should set it per-hop itself. }
  add_header(key, val);
end;

{ has_header / get_header / remove_header take the key VERBATIM. Only
  add_header folds — measured against CPython, which answers False for
  `has_header('content-type')` after `add_header('CONTENT-TYPE', ...)` stored
  it as 'Content-type'. Folding on the way in AND on the way out looks tidier
  and is a different function from the one CPython exposes. }
function Request.has_header(const key: AnsiString): Boolean;
begin
  has_header := headers.indexof(key) >= 0;
end;

function Request.get_header(const key: AnsiString): Variant;
begin
  { dict.get(k) answers None for an absent key, which is exactly CPython's
    Request.get_header default — no sentinel argument needed. }
  get_header := headers.get(key);
end;

function Request.get_header(const key: AnsiString; const default_: Variant): Variant;
begin
  get_header := headers.get(key, default_);
end;

function Request.header_items: TPyList;
begin
  header_items := headers.itemlist;
end;

procedure Request.remove_header(const key: AnsiString);
begin
  if headers.indexof(key) >= 0 then
    headers.remove(key);
end;



{ ---- urlopen ------------------------------------------------------------- }

{ Bytes in, Pascal string out. A `data` argument is bytes in CPython (a str is
  a TypeError there), but NilPy hands a str straight through as an AnsiString,
  so both are accepted and a str is NOT rejected — being laxer than CPython in
  a direction no working CPython program can observe is a dialect choice, not a
  defect (the NilPy upward-compatibility rule in CLAUDE.md). }
function DataToString(const data: Variant; var isNone: Boolean): AnsiString;
var o: TObject; b: TPyBytes; i: Integer; s: AnsiString;
begin
  DataToString := '';
  isNone := data = pynone;
  if isNone then Exit;
  o := nil;
  if pyvar_is_objtag(data) then o := TObject(pyvarobj(data));
  if (o <> nil) and (o is TPyBytes) then
  begin
    b := TPyBytes(o);
    s := '';
    for i := 0 to b.count - 1 do s := s + Chr(b.at(i));
    DataToString := s;
    Exit;
  end;
  DataToString := pystr_of(data);
end;

{ Render the Request's header dict as the CRLF-terminated block http.pas's
  extraHeaders argument wants. }
function HeaderBlock(d: TPyDict): AnsiString;
var i: Integer; keys: TPyList; k: Variant; r: AnsiString;
begin
  r := '';
  if d <> nil then
  begin
    keys := d.keylist;
    for i := 0 to keys.count - 1 do
    begin
      k := keys.at(i);
      r := r + pystr_of(k) + ': ' + pystr_of(d.fetch(k)) + #13#10;
    end;
  end;
  HeaderBlock := r;
end;

function HasHeaderNamed(const block, name: AnsiString): Boolean;
begin
  HasHeaderNamed := HttpHeaderValue(block, name) <> '';
end;

{ CPython's reason for a status when the server sent none. Only the handful a
  local server realistically omits — an unknown code answers '' rather than a
  guessed phrase, because inventing a reason is exactly the approximation this
  shim refuses elsewhere. }
function DefaultReason(status: Integer): AnsiString;
begin
  case status of
    200: DefaultReason := 'OK';
    201: DefaultReason := 'Created';
    204: DefaultReason := 'No Content';
    301: DefaultReason := 'Moved Permanently';
    302: DefaultReason := 'Found';
    304: DefaultReason := 'Not Modified';
    400: DefaultReason := 'Bad Request';
    401: DefaultReason := 'Unauthorized';
    403: DefaultReason := 'Forbidden';
    404: DefaultReason := 'Not Found';
    500: DefaultReason := 'Internal Server Error';
    502: DefaultReason := 'Bad Gateway';
    503: DefaultReason := 'Service Unavailable';
  else
    DefaultReason := '';
  end;
end;

const
  { CPython's HTTPRedirectHandler.max_redirections. }
  MAX_REDIRECTS = 10;

function urlopen(const url: Variant; const data: Variant;
                 timeout: Integer): HTTPResponse;
var
  req: Request;
  o: TObject;
  target, method, body, extra, host, path, loc, reason: AnsiString;
  port, hops: Integer;
  isTls, bodyIsNone: Boolean;
  r: THttpResponse;
begin
  { A non-default timeout cannot be honoured — see the unit header. Refusing
    here, at the call, is the whole point: the caller asked for a bound. }
  if timeout <> TIMEOUT_DEFAULT then
    raise URLError.Create(
      'urlopen(timeout=...) is not supported: the RTL HTTP client ' +
      '(lib/rtl/http.pas) has no request timeout, so honouring the argument ' +
      'is impossible and ignoring it would turn a bounded wait into an ' +
      'unbounded one. Omit timeout to block, or file a ticket for a timeout ' +
      'in http.pas.');

  { `url` is a str or a Request — CPython accepts either and so does this. }
  req := nil;
  o := nil;
  if pyvar_is_objtag(url) then o := TObject(pyvarobj(url));
  if (o <> nil) and (o is Request) then req := Request(o);
  if req = nil then
    req := Request.Create(pystr_of(url), pynone, pynone, '');

  { A `data` argument to urlopen overrides the Request's, which is CPython's
    rule (the Request keeps its own only when urlopen was given none). Through
    ArgOrNone, or an OMITTED data silently clobbers the Request's own. }
  if ArgOrNone(data) <> pynone then req.data := ArgOrNone(data);

  body := DataToString(req.data, bodyIsNone);
  method := req.get_method;
  extra := HeaderBlock(req.headers);

  { CPython's AbstractHTTPHandler adds these two when there is a body and the
    caller did not set them. Reproduced because a server that gets a POST with
    no Content-Type behaves differently, and the difference would look like our
    bug rather than a missing default. }
  if not bodyIsNone then
  begin
    if not HasHeaderNamed(extra, 'Content-Type') then
      extra := extra + 'Content-Type: application/x-www-form-urlencoded'#13#10;
  end;

  target := req.full_url;
  hops := 0;

  while True do
  begin
    if not HttpParseUrl(target, host, port, path, isTls) then
      raise URLError.Create('unknown url type: ' + target +
        ' (this build speaks http:// and https:// only)');

    if isTls and (not TlsAvailable) then
      raise URLError.Create(
        'https requires a TLS backend, and none is registered. lib/rtl ships ' +
        'two and neither installs itself — the program picks: ' +
        'tls13_native.Tls13NativeRegister (syscall-only) or ' +
        'tls_openssl.OpenSslTlsRegisterEx (dlopen libssl). Call one before ' +
        'urlopen, or use an http:// url.');

    r := HttpExec(method, target, extra, body);

    if not r.Ok then
      raise URLError.Create('could not reach ' + host + ':' + IntToStr(port));

    { Follow redirects the way CPython's default opener does, including the
      303/302-after-POST rewrite to GET that every real client performs. }
    if (r.Status >= 300) and (r.Status <= 399) and (r.Status <> 304) then
    begin
      loc := HttpResponseHeader(r, 'Location');
      if loc <> '' then
      begin
        Inc(hops);
        if hops > MAX_REDIRECTS then
          raise HTTPError.Create(target, r.Status, 'Redirect loop detected',
                                 HTTPMessage.Create(r.Headers), r.Body);
        { Resolved through http.pas's own resolver so a relative Location
          behaves identically here and in HttpGetFollow — one implementation,
          not a second one written in the shim. }
        target := HttpResolveUrl(target, loc);
        if (r.Status = 303) or
           ((r.Status = 301) or (r.Status = 302)) and (method = 'POST') then
        begin
          method := 'GET';
          body := '';
          bodyIsNone := True;
        end;
        Continue;
      end;
    end;

    Break;
  end;

  reason := r.Reason;
  if reason = '' then reason := DefaultReason(r.Status);

  { CPython's HTTPErrorProcessor raises for anything outside 2xx once
    redirects are done — that is what makes `urlopen` on a 404 raise rather
    than answer, and code depends on it heavily. }
  if (r.Status < 200) or (r.Status > 299) then
    raise HTTPError.Create(target, r.Status, reason,
                           HTTPMessage.Create(r.Headers), r.Body);

  urlopen := HTTPResponse.Create(target, r.Status, reason, r.Headers, r.Body);
end;

function urlretrieve(const url: Variant): TPyList;
begin
  raise URLError.Create(
    'urlretrieve(url) without a filename is not supported: CPython invents a ' +
    'temporary file, which needs a location/permissions/cleanup policy a ' +
    'compatibility shim should not pick for the program. Pass a filename.');
  { unreachable; present so the function has a result on every path }
  urlretrieve := TPyList.Create;
end;

function urlretrieve(const url: Variant; const filename: AnsiString): TPyList;
var resp: HTTPResponse; fd: Integer; l: TPyList;
    declared, payload: AnsiString; want: Integer; wrote: Int64;
begin
  resp := urlopen(url);

  { CPython raises ContentTooShortError when the body is shorter than the
    Content-Length said it would be — a truncated download that would
    otherwise be written out and read back as a valid short file. }
  declared := resp.headers.get('Content-Length', '');
  if declared <> '' then
  begin
    want := StrToIntDef(declared, -1);
    if (want >= 0) and (Length(resp.body) < want) then
      raise ContentTooShortError.Create(
        'retrieval incomplete: got ' + IntToStr(Length(resp.body)) +
        ' out of ' + declared + ' bytes', resp.body);
  end;

  { PalOpen/PalWrite rather than a Pascal file variable: the body is BYTES and
    text I/O would be free to translate them. A downloaded png that survives
    urlretrieve only on a platform whose line endings happen to match is the
    kind of wrong-value bug this project treats as worst. }
  fd := PalOpen(PChar(filename),
                PAL_OPEN_WRITE or PAL_OPEN_CREATE or PAL_OPEN_TRUNC, 438);
  if fd < 0 then
    raise URLError.Create('cannot open ' + filename + ' for writing');
  payload := resp.body;
  wrote := 0;
  if Length(payload) > 0 then
    wrote := PalWrite(fd, @payload[1], Length(payload));
  PalClose(fd);
  if wrote <> Length(payload) then
    raise ContentTooShortError.Create(
      'short write to ' + filename + ': ' + IntToStr(wrote) + ' of ' +
      IntToStr(Length(payload)) + ' bytes', payload);

  l := TPyList.Create;
  l.append(filename);
  l.append(resp.headers);
  urlretrieve := tuple(l);
end;

end.
