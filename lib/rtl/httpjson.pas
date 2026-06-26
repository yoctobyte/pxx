unit httpjson;
{ JSON-over-HTTP convenience — ties the native HTTP client (http) to the JSON
  codec (json) for REST-style calls. Kept separate from http.pas so plain HTTP
  users don't pull the JSON unit.

  Each call returns the parsed JSON tree (caller owns it — TJSONValue.FreeTree)
  and reports success via `ok` (False on transport failure or a non-JSON body;
  the result is nil then). Async variants run on the scheduler reactor — call
  from a coroutine, drive with RunUntilDone. }

interface

uses http, json;

function HttpGetJson(const url: AnsiString; var ok: Boolean): TJSONValue;
function HttpPostJson(const url: AnsiString; body: TJSONValue; var ok: Boolean): TJSONValue;
function HttpGetJsonAsync(const url: AnsiString; var ok: Boolean): TJSONValue;
function HttpPostJsonAsync(const url: AnsiString; body: TJSONValue; var ok: Boolean): TJSONValue;

{ Parse a JSON document, swallowing EJSONError into ok=False (result nil). }
function JsonParseSafe(const src: AnsiString; var ok: Boolean): TJSONValue;

implementation

function JsonParseSafe(const src: AnsiString; var ok: Boolean): TJSONValue;
begin
  ok := False; Result := nil;
  try
    Result := JSONParse(src);
    ok := Result <> nil;
  except
    on e: EJSONError do begin ok := False; Result := nil; end;
  end;
end;

function HttpGetJson(const url: AnsiString; var ok: Boolean): TJSONValue;
var r: THttpResponse;
begin
  ok := False; Result := nil;
  r := HttpGet(url);
  if not r.Ok then Exit;
  Result := JsonParseSafe(r.Body, ok);
end;

function HttpPostJson(const url: AnsiString; body: TJSONValue; var ok: Boolean): TJSONValue;
var r: THttpResponse;
begin
  ok := False; Result := nil;
  r := HttpPost(url, 'application/json', body.ToString(False));
  if not r.Ok then Exit;
  Result := JsonParseSafe(r.Body, ok);
end;

function HttpGetJsonAsync(const url: AnsiString; var ok: Boolean): TJSONValue;
var r: THttpResponse;
begin
  ok := False; Result := nil;
  r := HttpGetAsync(url);
  if not r.Ok then Exit;
  Result := JsonParseSafe(r.Body, ok);
end;

function HttpPostJsonAsync(const url: AnsiString; body: TJSONValue; var ok: Boolean): TJSONValue;
var r: THttpResponse;
begin
  ok := False; Result := nil;
  r := HttpPostAsync(url, 'application/json', body.ToString(False));
  if not r.Ok then Exit;
  Result := JsonParseSafe(r.Body, ok);
end;

end.
