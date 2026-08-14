unit mimic_string;
{ Python's `string` module — the constants and `capwords`.

  It exists first of all so that `import string` in a `.npy` stops resolving to
  the C header `string.h`. A NilPy import may legitimately name a C header (the
  wrapper-free NilPy-to-C arc: `import sqlite3`, `import stdlib`), and the
  resolver tries a `mimic_` shim BEFORE a host header for exactly this reason —
  but that ordering is inert while no shim of the name exists, so `import
  string` pulled /usr/include/string.h and the failure surfaced later as
  `undefined variable (ascii_lowercase)`, pointing at the attribute instead of
  at the import. bug-nilpy-python-import-resolves-against-c-headers

  Values are CPython's own, verified against 3.12 rather than typed from
  memory — `punctuation` in particular is easy to get subtly wrong (it is
  ASCII 33..47, 58..64, 91..96, 123..126, in that order) and nothing would
  notice until a tokeniser behaved differently.

  `whitespace` is space, tab, newline, carriage return, vertical tab, formfeed —
  written by code point, since three of the six have no readable spelling in a
  Pascal string literal. }

interface

const
  ascii_lowercase: AnsiString = 'abcdefghijklmnopqrstuvwxyz';
  ascii_uppercase: AnsiString = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  ascii_letters: AnsiString =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  digits: AnsiString = '0123456789';
  hexdigits: AnsiString = '0123456789abcdefABCDEF';
  octdigits: AnsiString = '01234567';
  punctuation: AnsiString = '!"#$%&' + #39 + '()*+,-./:;<=>?@[\]^_`{|}~';
  whitespace: AnsiString = ' ' + #9 + #10 + #13 + #11 + #12;

{ `string.capwords(s)` — split on whitespace, capitalise each word, join with a
  single space. NOT the same as `s.title()`, which upper-cases after every
  non-letter: `capwords("don't")` is "Don't" while `"don't".title()` is
  "Don'T". Python ships both for that reason, so the difference is the point of
  having this. }
function capwords(const s: AnsiString): AnsiString;

implementation

function capwords(const s: AnsiString): AnsiString;
var i, k, n: Integer; word: AnsiString; first: Boolean;
begin
  Result := '';
  first := True;
  i := 1;
  n := Length(s);
  while i <= n do
  begin
    { skip the run of whitespace — capwords collapses it, which is why the
      result is joined with a single space rather than rebuilt in place }
    while (i <= n) and ((s[i] = ' ') or (s[i] = #9) or (s[i] = #10) or
                        (s[i] = #13) or (s[i] = #11) or (s[i] = #12)) do Inc(i);
    if i > n then Break;
    word := '';
    while (i <= n) and not ((s[i] = ' ') or (s[i] = #9) or (s[i] = #10) or
                            (s[i] = #13) or (s[i] = #11) or (s[i] = #12)) do
    begin
      word := word + s[i];
      Inc(i);
    end;
    { capitalise: first character up, the REST DOWN — `capwords("HELLO")` is
      "Hello", not "HELLO" }
    if Length(word) > 0 then
    begin
      if (word[1] >= 'a') and (word[1] <= 'z') then
        word[1] := Chr(Ord(word[1]) - 32);
      { `k`, not `i` — `i` is the OUTER scan position and reusing it here
        would restart the scan inside the word just consumed. }
      for k := 2 to Length(word) do
        if (word[k] >= 'A') and (word[k] <= 'Z') then
          word[k] := Chr(Ord(word[k]) + 32);
    end;
    if not first then Result := Result + ' ';
    Result := Result + word;
    first := False;
  end;
end;

end.
