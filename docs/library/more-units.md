---
title: More units
order: 57
---

# More units

Short entries for units that have no page of their own yet. Each one says what
the unit is, gives an example, and lists the limits a user meets first. The
examples were run with pin v451 (sha256 `d9b7226769cc`) from a release archive
on x86-64 Linux on 2026-09-29. Where a unit stands in for a CPython module, the
same program was run under CPython 3 and the outputs compared.

Units for Pascal:

- [`bignum`](#bignum-arbitrary-precision-integers): integers of any size.
- [`zlib`](#zlib-deflate-and-inflate): deflate compression, for Pascal and Nil Python.
- [`hashing`, `sha256`, `sha512`](#hashing-sha256-and-sha512-checksums-and-digests): CRC32, Adler32, SHA-2, HMAC and HKDF.
- [`png` and `image`](#png-and-image-reading-and-writing-png-files): reading and writing PNG files.
- [`strutils`](#strutils-fpcs-string-helpers-in-part): a part of FPC's `StrUtils`.
- [`dateutils`](#dateutils-fpcs-date-helpers-in-part): a part of FPC's `DateUtils`.
- [`collections`](#collections-a-generic-list): a generic list.
- [`contnrs`](#contnrs-object-lists): FPC's object lists.
- [`regex`](#regex-regular-expressions-for-pascal): regular expressions.
- [`random`](#random-seeded-generators): seeded generators.
- [`base64`](#base64-encoding-bytes-as-text): Base64, for Pascal and Nil Python.
- [`httpjson`](#httpjson-json-over-http): JSON over HTTP.

Modules for Nil Python:

- [`configparser`](#configparser-ini-files): INI settings files.
- [`pathlib`](#pathlib-paths-as-objects): paths as objects.
- [`urllib.parse`](#urllibparse-splitting-a-url): splitting and quoting URLs.
- [`sqlite3`](#sqlite3-the-db-api-over-the-system-library): SQLite through Python's DB-API.
- [`tempfile`](#tempfile-temporary-files-and-directories): temporary files and directories.
- [`re`](#re-regular-expressions-for-nil-python): regular expressions.
- [`random`](#random-for-nil-python): random numbers.
- [`collections`](#collections-counter-and-deque): `Counter` and `deque`.
- [`html`](#html-escaping-text-for-html): escaping text for HTML.
- [`markdown`](#markdown-readme-shaped-markdown-to-html): Markdown to HTML.
- [`subprocess`](#subprocess-running-other-programs): running other programs.

## `bignum`: arbitrary-precision integers

`TBigInt` is a signed integer of any size, with the operators `+ - * div mod`
and the comparisons. Integers and strings come in through `BigFromInt` and
`BigFromStr`, and results go out through `BigToStr`. `BigDivMod` and
`BigModPow` cover division with remainder and modular powers.

```pascal
program bn;
uses bignum;
var f, p, q, r: TBigInt; i: Integer;
begin
  f := BigFromInt(1);
  for i := 2 to 30 do f := f * BigFromInt(i);
  WriteLn(BigToStr(f));
  p := BigFromStr('-123456789012345678901234567890');
  BigDivMod(p, BigFromInt(97), q, r);
  WriteLn(BigToStr(q), ' ', BigToStr(r));
  WriteLn(BigToStr(BigModPow(BigFromInt(2), BigFromInt(1000), BigFromStr('1000000007'))));
  WriteLn(f > p, ' ', p < BigFromInt(0));
end.
```

```text
265252859812191058636308480000000
-1272750402189130710322005854 -52
688423210
TRUE TRUE
```

Python's integers give the same four lines. Division truncates toward zero and
the remainder takes the sign of the dividend, as `div` and `mod` do on `Int64`.

Limits:

- There is no implicit conversion: `f * 2` does not compile, write
  `f * BigFromInt(2)`.
- The algorithms are the schoolbook ones. 3000! (9,131 digits) took 0.12 s,
  which is fine for most uses but far slower than GMP on large numbers.
- Only base 10 goes in and out as text.

`examples/bignum` computes large factorials and powers with it.

## `zlib`: deflate and inflate

One unit serves both languages. From Pascal, `DeflateZlib` compresses a byte
array and `InflateZlib` decompresses one. `InflateGzip` reads the gzip wrapper.
From Nil Python, `import zlib` gives `compress`, `decompress`, `crc32` and
`adler32`. Its streams are ordinary zlib streams: CPython's `zlib` reads what it
writes, and it reads what CPython writes.

```pascal
program zp;
uses hashing, zlib;
var src, zipped, back: TByteArray; i: Integer; err: AnsiString;
begin
  SetLength(src, 4000);
  for i := 0 to 3999 do src[i] := Ord('a') + (i mod 7);
  DeflateZlib(src, zipped, 6);
  WriteLn(Length(src), ' -> ', Length(zipped));
  WriteLn(InflateZlib(zipped, back, err), ' ', Length(back) = Length(src));
end.
```

```text
4000 -> 35
TRUE TRUE
```

```python
import zlib

data = b"hello hello hello hello zlib" * 20
packed = zlib.compress(data)
print(len(data), len(packed) < len(data))
print(zlib.decompress(packed) == data)
print(zlib.crc32(data), zlib.adler32(data))
```

```text
560 True
True
587555724 1067635221
```

CPython prints the same checksums for the same data.

Limits:

- `TByteArray` here is `hashing`'s dynamic `array of Byte`. `sysutils`
  declares a different, fixed-size `TByteArray`, and the unit named last in
  `uses` wins. With `uses hashing, zlib, sysutils` the program above stops at
  `SetLength: not a dynamic array`. Put `sysutils` before `hashing`, or write
  `hashing.TByteArray`.
- The Python surface is the four functions above: there is no `compressobj`
  or `decompressobj` for streaming.

## `hashing`, `sha256` and `sha512`: checksums and digests

`hashing` has CRC32 (the polynomial PNG, zlib and gzip use) and Adler32, over a
`TByteArray`. `sha256` has SHA-256, HMAC-SHA256 and HKDF-SHA256, and `sha512`
has SHA-512. The SHA units take and return byte strings (`AnsiString`, one
byte per character). A digest comes back as raw bytes, and `Sha256Hex` turns
any byte string into lower-case hex, including a SHA-512 digest.

```pascal
program hs;
uses sysutils, hashing, sha256, sha512;
var b: TByteArray; prk: AnsiString; i: Integer;
begin
  WriteLn(Sha256Hex(Sha256('abc')));
  WriteLn(Sha256Hex(HmacSha256('key', 'The quick brown fox jumps over the lazy dog')));
  WriteLn(Sha256Hex(Sha512('abc')));
  prk := HkdfExtract(#$00#$01#$02#$03#$04#$05#$06#$07#$08#$09#$0a#$0b#$0c,
                     StringOfChar(#$0b, 22));
  WriteLn(Sha256Hex(HkdfExpand(prk, #$f0#$f1#$f2#$f3#$f4#$f5#$f6#$f7#$f8#$f9, 42)));
  SetLength(b, 5);
  for i := 0 to 4 do b[i] := Ord('hello'[i + 1]);
  WriteLn(CRC32Bytes(b), ' ', Adler32(b));
end.
```

```text
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8
ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f
3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865
907060870 103547413
```

CPython's `hashlib`, `hmac` and `zlib` give the same values. The HKDF line is
test case 1 of RFC 5869. Hashing 1 MB with `Sha256` took 0.13 s.

Limits:

- The SHA functions work on a whole string in memory. There is no streaming
  interface to feed data in pieces. CRC32 has one: `CRC32Init`,
  `CRC32Update` for each byte, `CRC32Final`.
- For Pascal there is no SHA-1, MD5, SHA-384 or SHA-224 unit. From Nil Python,
  `import hashlib` is a separate shim with its own list of algorithms.
- `StringOfChar`, used above, needs `uses sysutils` in PXX. FPC has it in
  `System`.

## `png` and `image`: reading and writing PNG files

`image` holds a bitmap: `TImage` has `Width`, `Height` and `Pixels`, an array
of 8-bit `TRGBA` values in row order. `png` reads a PNG file's bytes into a
`TImage` with `PngDecodeRGBA`, and writes one with `PngEncodeRGBA`. No
compression library is needed.

```pascal
program pe;
uses sysutils, hashing, image, png;
var img, back: TImage; x, y: Integer; bytes: TByteArray;
begin
  ImageInit(img, 64, 32);
  for y := 0 to 31 do
    for x := 0 to 63 do
      ImageSetPixel(img, x, y, MakeRGBA(x * 4, y * 8, 128, 255));
  PngEncodeRGBA(img, bytes);
  WriteLn(Length(bytes), ' bytes');
  WriteLn(PngDecodeRGBA(bytes, back), ' ', back.Width, 'x', back.Height, ' ',
          ImageGetPixel(back, 10, 3).R, ' ', ImageGetPixel(back, 10, 3).G);
end.
```

```text
2513 bytes
TRUE 64x32 40 24
```

The encoder writes 8-bit RGBA (colour type 6), which every PNG reader
accepts; the Python imaging library PIL read the file above back with every
pixel equal. The decoder reads every non-interlaced colour type: files written
by PIL as RGBA, RGB, grayscale, grayscale with alpha, palette, 1-bit and
16-bit grayscale all decoded to the same pixels PIL reports. Every result is
widened to 8-bit RGBA: a 16-bit sample keeps its high byte.
`PngLastColourType` and `PngLastBitDepth` report what the file was.

Limits:

- An interlaced (Adam7) file is refused, and `PngLastError` says
  `interlaced (adam7) png is not supported`.
- The encoder writes only 8-bit RGBA, with no palette or grayscale output, so
  a picture with few colours makes a larger file than it needs to.
- The encoder writes only the `IHDR`, `IDAT` and `IEND` chunks: no text,
  gamma or colour profile. When reading, a file with a text chunk decoded to
  the right pixels. Other extra chunks were not tried.
- Files are passed as a `TByteArray`, so the `uses` order rule under
  [`zlib`](#zlib-deflate-and-inflate) applies: `sysutils` before `hashing`.

## `strutils`: FPC's string helpers, in part

26 routines from FPC's `StrUtils`: `LeftStr`, `RightStr`, `MidStr`,
`DupeString`, `PosEx`, `ReverseString`, `AddChar`, `AddCharR`, the
`AnsiContains`/`AnsiStarts`/`AnsiEnds`/`AnsiReplace`/`AnsiIndex` routines in
their `Str` and `Text` forms, `WordCount`, `ExtractWord`, `WordPosition`,
`ExtractWordPos`, `ExtractDelimited`, `ExtractSubstr`, `IfThen` and
`SplitString`.

```pascal
program su;
{$mode objfpc}{$H+}
uses sysutils, strutils;
var p: Integer; parts: TStringArray; i: Integer;
const s = 'the quick brown fox';
begin
  WriteLn(LeftStr(s, 3), '|', RightStr(s, 3), '|', MidStr(s, 5, 5), '|', DupeString('ab', 3));
  WriteLn(PosEx('o', s, 14), ' ', ReverseString('abc'), ' ', AddChar('*', 'x', 4));
  WriteLn(AnsiContainsText(s, 'QUICK'), ' ', AnsiReplaceText('A-b-a', 'a', 'x'),
          ' ', AnsiIndexStr('fox', ['the', 'fox']));
  WriteLn(WordCount(s, [' ']), ' ', ExtractWord(3, s, [' ']), ' ',
          ExtractDelimited(3, 'a,b,,c', [',']), '|');
  p := 1;
  Write(ExtractSubstr('k=v;x', p, ['=', ';']), ' ');
  WriteLn(ExtractSubstr('k=v;x', p, ['=', ';']), ' ', p);
  parts := SplitString('a b  c', ' ');
  Write(Length(parts), ':');
  for i := 0 to High(parts) do Write(' [', parts[i], ']');
  WriteLn;
end.
```

```text
the|fox|quick|ababab
18 cba ***x
TRUE x-b-x 1
4 brown |
k v 5
4: [a] [b] [] [c]
```

FPC 3.2.2 prints the same, and a program calling all 26 routines printed the
same as FPC on every line.

Limits: FPC's `StrUtils` has many more routines. Among the common ones,
`ContainsStr`, `StartsStr`, `EndsStr`, `ReplaceStr`, `ReplaceText`, `RPos`,
`NPos`, `PosSet`, `DelSpace`, `PadLeft`, `StuffString`, `IntToRoman` and
`Soundex` are missing: a call to one does not compile.

## `dateutils`: FPC's date helpers, in part

Seven routines from FPC's `DateUtils`: `YearOf`, `MonthOf`, `DayOf`,
`HourOf`, `MinuteOf`, `SecondOf` and `EncodeDateTime`. `TDateTime` itself, `Now`,
`FormatDateTime`, `DayOfWeek` and `IsLeapYear` are in `sysutils`, as in FPC.

```pascal
program du;
{$mode objfpc}{$H+}
uses sysutils, dateutils;
var t: TDateTime;
begin
  t := EncodeDateTime(2026, 9, 29, 14, 5, 42, 250);
  WriteLn(YearOf(t), ' ', MonthOf(t), ' ', DayOf(t), ' ', HourOf(t), ' ', MinuteOf(t), ' ', SecondOf(t));
  WriteLn(FormatDateTime('yyyy-mm-dd hh:nn:ss', t));
  WriteLn(t:0:6);
end.
```

```text
2026 9 29 14 5 42
2026-09-29 14:05:42
46294.587295
```

FPC 3.2.2 prints the same.

Limits: the rest of `DateUtils` is missing. `IncDay`, `DaysBetween`,
`DateTimeToUnix`, `UnixToDateTime`, `DayOfTheWeek` and `MilliSecondOf` do not
compile, for example.

## `collections`: a generic list

`generic TList<T>`, a growable list with `Add`, `Get`, `Put`, `Count` and
`Clear`. This is PXX's own small unit, not FPC's `Generics.Collections`, so
there is no FPC program to compare against. The sums below are checked against
the same arithmetic in Python.

```pascal
program col;
{$define PXX_MANAGED_STRING}
uses collections;
type
  TIntList = specialize TList<Integer>;
  TStrList = specialize TList<AnsiString>;
var a: TIntList; s: TStrList; i, sum: Integer;
begin
  a := TIntList.Create;
  for i := 1 to 1000 do a.Add(i * i);
  sum := 0;
  for i := 0 to a.Count - 1 do sum := sum + a.Get(i);
  a.Put(0, -1);
  WriteLn(a.Count, ' ', sum, ' ', a.Get(0), ' ', a.Get(999));
  s := TStrList.Create;
  s.Add('alpha'); s.Add('beta');
  WriteLn(s.Count, ' ', s.Get(1));
  a.Clear;
  WriteLn(a.Count);
end.
```

```text
1000 333833500 -1 1000000
2 beta
0
```

Limits:

- A list of `AnsiString` needs `{$define PXX_MANAGED_STRING}` before
  `uses collections`, as above.
- There is no indexer (`a[i]`), no `for ... in`, no `Delete`, `Insert`,
  `IndexOf` or `Sort`. Programs written for FPC's `Generics.Collections`
  (`TList<T>`, `TDictionary<K,V>`) do not compile against this unit.

## `contnrs`: object lists

FPC's `TFPObjectList` and `TFPHashObjectList`: `Add`, `Delete`, `Remove`,
`Extract`, `IndexOf`, `Insert`, `Move`, `Exchange`, `Sort`, the default
`Items[]` property and `OwnsObjects`. The hash list adds `Add(name, object)`,
`Find`, `FindIndexOf` and `NameOfIndex`. Its lookup is a linear search, not a
hash table: the results are FPC's, only slower on long lists.

```pascal
program cnt;
{$mode objfpc}{$H+}
uses classes, contnrs;
type
  TItem = class
    N: Integer;
    constructor Create(AN: Integer);
  end;
constructor TItem.Create(AN: Integer); begin N := AN; end;
function ByN(a, b: Pointer): Integer; begin Result := TItem(a).N - TItem(b).N; end;
var l: TFPObjectList; h: TFPHashObjectList; i: Integer;
begin
  l := TFPObjectList.Create(False);
  l.Add(TItem.Create(3)); l.Add(TItem.Create(1)); l.Add(TItem.Create(2));
  l.Sort(@ByN);
  for i := 0 to l.Count - 1 do Write(TItem(l[i]).N, ' ');
  WriteLn(l.IndexOf(l[2]));
  for i := 0 to l.Count - 1 do TItem(l[i]).Free;
  l.Free;
  h := TFPHashObjectList.Create(False);
  h.Add('beta', TItem.Create(20)); h.Add('alpha', TItem.Create(10));
  WriteLn(TItem(h.Find('alpha')).N, ' ', h.Find('gamma') = nil, ' ',
          h.FindIndexOf('beta'), ' ', h.NameOfIndex(1));
  for i := 0 to h.Count - 1 do TItem(h[i]).Free;
  h.Free;
end.
```

```text
1 2 3 2
10 TRUE 0 alpha
```

FPC 3.2.2 prints the same.

**Warning, on v451: an owning list does not run your destructor.** With
`OwnsObjects` true (the default for `Create`), `Delete`, `Clear`, `Remove`
and `Free` call `Free` on each item through a `TObject`, and on v451 a `Free`
through `TObject` made inside a unit does not reach an overridden
`Destroy`. The list's items are never destroyed: a class that counts its
destructor calls counts 0 where FPC counts every item. Until this is fixed,
create the list with `Create(False)` and free each item through its own class
type, `TItem(l[i]).Free`, as the example does. That works in a program and in
a unit.

## `regex`: regular expressions for Pascal

The engine behind Nil Python's `re`, callable from Pascal. `ReCompile(pattern,
flags)` returns a `TRegex` record, whose `ok` and `error` fields say whether
the pattern was understood. `ReMatch`, `ReFullMatch`, `ReSearch` and
`ReSearchFrom` return a `TReMatch`, and `ReGroup(m, s, n)` gives group `n` of
subject `s`. `ReFindAll`, `ReReplace` and `ReQuickMatch` complete it. The
flags are `RE_IGNORECASE`, `RE_VERBOSE` and `RE_DOTALL`, Python's `re.I`,
`re.X` and `re.S`.

```pascal
program rx;
uses regex;
var r: TRegex; m: TReMatch;
begin
  r := ReCompile('(\w+)-(\d+)', 0);
  m := ReSearch(r, 'see item-42 here');
  WriteLn(m.matched, ' ', ReGroup(m, 'see item-42 here', 1), ' ', ReGroup(m, 'see item-42 here', 2));
  r := ReCompile('foo(?=bar)', 0);
  WriteLn(r.ok, ' ', r.error);
end.
```

```text
TRUE item 42
FALSE only (?:...) group extensions are supported
```

The syntax is Python's. Lookahead and lookbehind, backreferences such as
`\1`, named groups `(?P<name>...)` and possessive quantifiers such as `a++`
are not supported. `ReCompile` reports each one through `ok` and `error`;
check `ok` before searching. The [`re`](#re-regular-expressions-for-nil-python)
entry lists what the same engine does from Python.

## `random`: seeded generators

xoshiro256** seeded through SplitMix64, as a global generator (`XoshiroSeed`,
`XoshiroNext`, `Random64`, `RandomDouble`, `RandRange`, `RandomBytes`) and as a
state record you own (`TRandomState` with `RandomStateSeed`, `RandomStateNext`,
`RandomStateRange`, `RandomStateDouble`, `RandomStateBytes` and
`RandomStateSplit`). `OSEntropyBytes` and `OSEntropy64` read the
operating system's generator (`getrandom` on Linux), and `XoshiroRandomize`
reseeds from hardware entropy, then the operating system. The built-in `Random` and `RandSeed` keep
working alongside.

```pascal
program rnd;
uses random;
var st: TRandomState; i, lo, hi, v: Integer; d: Double;
begin
  XoshiroSeed(42);
  for i := 1 to 3 do WriteLn(XoshiroNext);
  RandomStateSeed(st, 42);
  WriteLn(RandomStateNext(st));
  lo := 1000; hi := -1000;
  for i := 1 to 100000 do
  begin
    v := RandomStateRange(st, 1, 6);
    if v < lo then lo := v;
    if v > hi then hi := v;
  end;
  d := RandomStateDouble(st);
  WriteLn(lo, ' ', hi, ' ', (d >= 0) and (d < 1));
end.
```

```text
1546998764402558742
6990951692964543102
12544586762248559009
1546998764402558742
1 6 TRUE
```

The first three numbers are those of the published xoshiro256** and SplitMix64
algorithms, written out in Python as the reference. The same program prints
the same lines on i386 and aarch64. `RandomStateRange(st, lo, hi)` includes
both ends. A seeded sequence is the same on every run and every target, and
none of these generators is fit for keys or tokens: use `OSEntropyBytes` for
those.

## `base64`: encoding bytes as text

One unit for both languages. From Pascal: `Base64Encode` and `Base64Decode`
over `hashing`'s `TByteArray`, and `Base64EncodeStr` and `Base64DecodeStr` over
strings. From Nil Python: `base64.b64encode` and `base64.b64decode`.

```pascal
program b64;
uses sysutils, hashing, base64;
var data: TByteArray;
begin
  WriteLn(Base64EncodeStr('user:pass'));
  WriteLn(Base64EncodeStr('a'), '|', Base64EncodeStr('ab'), '|', Base64EncodeStr('abc'));
  WriteLn(Base64DecodeStr('dXNlcjpw' + #10 + 'YXNz'));
  WriteLn(Base64Decode('dXNl*cjpwYXNz', data));
end.
```

```text
dXNlcjpwYXNz
YQ==|YWI=|YWJj
user:pass
FALSE
```

```python
import base64

e = base64.b64encode(b"\x00\xffhello")
print(e, base64.b64decode(e))
print(base64.b64decode("dXNlcjpw\nYXNz"))
```

```text
b'AP9oZWxsbw==' b'\x00\xffhello'
b'user:pass'
```

CPython prints the same, and gives the same encodings as the Pascal lines.
Line breaks in the input are skipped, as in CPython.

Where it differs from CPython, on v451:

- A character outside the alphabet makes `b64decode` return `b''`.
  CPython by default drops such characters and decodes the rest
  (`b64decode("dXNl*cjpwYXNz")` is `b'user:pass'`), and with
  `validate=True` raises. From Pascal, `Base64Decode` returns FALSE.
- Only the two functions: `urlsafe_b64encode`, `b32encode`, `b16encode` and
  `encodebytes` are not there.
- As with `zlib`, put `sysutils` before `hashing` in `uses`, or the fixed-size
  `sysutils.TByteArray` wins.

## `httpjson`: JSON over HTTP

`HttpGetJson(url, ok)` and `HttpPostJson(url, body, ok)` fetch a URL and parse
the reply with the [`json`](./json.md) unit, and `JsonParseSafe(text, ok)`
parses without raising. Each returns `nil` with `ok` FALSE when the request
fails or the reply is not JSON. Free a result with `FreeTree`.

The example ran against a local test server on port 8765. `GET /info` answers
`{"name": "pxx", "tags": ["a", "b"], "n": 3}`, `POST /post` echoes the body
and its `Content-Type`, and `GET /notjson` answers the plain text `hello`.

```pascal
program hj;
uses sysutils, json, httpjson;
const base = 'http://127.0.0.1:8765';
var v, body, r: TJSONValue; ok: Boolean;
begin
  v := HttpGetJson(base + '/info', ok);
  WriteLn(ok, ' ', v.GetValue('name').AsString, ' ', v.GetValue('tags').Count, ' ', v.GetValue('n').AsInteger);
  v.FreeTree;
  body := JSONParse('{"k": [1, 2]}');
  r := HttpPostJson(base + '/post', body, ok);
  WriteLn(ok, ' ', r.ToString(False));
  r.FreeTree; body.FreeTree;
  v := HttpGetJson(base + '/notjson', ok);
  WriteLn(ok, ' ', v = nil);
  v := HttpGetJson('http://127.0.0.1:1/nothing', ok);
  WriteLn(ok, ' ', v = nil);
  v := JsonParseSafe('{bad', ok);
  WriteLn(ok, ' ', v = nil);
end.
```

```text
TRUE pxx 2 3
TRUE {"echo":{"k":[1,2]},"ct":"application/json"}
FALSE TRUE
FALSE TRUE
FALSE TRUE
```

The POST sends `Content-Type: application/json`. Only plain `http://` URLs
were tried for this entry. `HttpGetJsonAsync` and `HttpPostJsonAsync` exist
too; they were not run for this page.

## `configparser`: INI files

Python's `configparser`, for reading and writing settings files. Sections and
options keep the order they were added in, and there is no limit on how many
there are.

```python
import configparser

cfg = configparser.ConfigParser()
cfg.add_section("net")
cfg.set("net", "host", "example.org")
cfg.set("net", "port", "8080")
cfg.write("settings.ini")

back = configparser.ConfigParser()
back.read("settings.ini")
print(back.sections())
print(back.get("net", "port"))
print(repr(back.get("net", "missing")))
```

```text
['net']
8080
''
```

`cfg.write` accepts a file name, as above, or an open file, as in CPython
(`with open("o.ini", "w") as f: cfg.write(f)`). For an open file the output is
byte for byte what CPython writes.

Where it differs from CPython:

- A missing section or option reads as `''`. CPython raises `NoSectionError`
  or `NoOptionError`. Test with `has_section` and `has_option` first.
- There is no interpolation: a value holding `%(name)s` comes back as written.
  CPython substitutes it, or raises when the name is not defined.
- Passing a file name to `write` is PXX's own. CPython's `write` takes only an
  open file.

## `pathlib`: paths as objects

The part of Python's `pathlib` that programs use most: `Path(...)`, joining
with `/`, `name`, `stem`, `suffix`, `parent`, `exists()`, `is_file()`,
`is_dir()`, `mkdir(parents=, exist_ok=)`, `open()`, `read_text()`,
`write_text()`, `with_suffix()` and `with_name()`.

```python
from pathlib import Path

base = Path("out") / "logs"
base.mkdir(parents=True, exist_ok=True)
f = base / "day1.txt"
f.write_text("line one\n")
with f.open("a") as h:
    h.write("line two\n")
print(str(f), f.name, f.stem, f.suffix, str(f.parent))
print(f.exists(), f.is_file(), base.is_dir())
print(str(f.with_suffix(".csv")), str(f.with_name("x.txt")))
```

```text
out/logs/day1.txt day1.txt day1 .txt out/logs
True True True
out/logs/day1.csv out/logs/x.txt
```

CPython prints the same three lines.

Limits:

- There is no `glob`, `rglob`, `resolve`, `absolute`, `iterdir`, `PurePath` or
  Windows path flavour, and no comparison or hashing of paths. A call to one of
  them is a compile error, for example `Path has no method .glob()`.
- `read_text()` drops the file's last newline: on the file above it returns 17
  characters, where CPython returns 18. `open(path).read()` returns all 18.

## `urllib.parse`: splitting a URL

`urlparse`, `urlsplit`, `urlunparse`, `urlunsplit`, `quote` and `unquote`,
following the rules in CPython's own source.

```python
from urllib.parse import urlparse, urlsplit, quote, unquote

u = urlparse("HTTP://user@example.org:8080/a/b;p=1?q=2&r=3#top")
print(u.scheme, u.netloc, u.path, u.params, u.query, u.fragment)
s = urlsplit("data:text/html;base64,AAA")
print(s.scheme, s.path)
print(quote("a b/c&d"), unquote("a%20b%2Fc"))
```

```text
http user@example.org:8080 /a/b p=1 q=2&r=3 top
data text/html;base64,AAA
a%20b/c%26d a b/c
```

CPython prints the same lines. Note the lower-cased scheme, and that a `data:`
URL keeps its `;base64` in the path.

Limits: only these six functions. `urlencode`, `parse_qs`, `parse_qsl`,
`urljoin` and `quote_plus` are not there, and using one fails to compile
(`undefined variable (urlencode)`).

## `sqlite3`: the DB-API over the system library

`import sqlite3` gives a part of Python's DB-API over the system's
`libsqlite3.so.0`: `connect`, and on the connection `execute`, `executemany`,
`executescript`, `commit`, `rollback`, `close` and `total_changes`. A cursor
iterates, unpacks, and answers `fetchone` and `fetchall`. Errors raise
`sqlite3.Error`. The program is linked dynamically against SQLite, so the host
needs the library installed. To call SQLite's C functions directly instead,
see [Nil Python: C libraries](../targets/nil-python.md#c-libraries).

```python
import sqlite3

db = sqlite3.connect("shop.db")
db.execute("CREATE TABLE IF NOT EXISTS item(name TEXT, qty INTEGER, price REAL)")
db.executemany("INSERT INTO item VALUES (?, ?, ?)",
               [("apple", 3, 0.5), ("fig", 2, 1.25), ("pear", 5, 0.4)])
db.commit()
for name, qty, price in db.execute("SELECT name, qty, price FROM item WHERE qty > ? ORDER BY name", (2,)):
    print(name, qty, price)
print(db.execute("SELECT COUNT(*), SUM(qty) FROM item").fetchone())
print(db.total_changes)
try:
    db.execute("SELECT nope FROM item")
except sqlite3.Error as e:
    print("error:", e)
db.close()
```

```text
apple 3 0.5
pear 5 0.4
[3, 10]
3
error: no such column: nope
```

Limits:

- A row is a list, so it prints as `[3, 10]` where CPython prints `(3, 10)`.
  Indexing and unpacking work the same.
- Not there: `row_factory`, `detect_types`, `with` on a connection, an explicit
  `cursor()`, `description`, `lastrowid`, `rowcount`, named (`:name`)
  parameters, and the exception subclasses such as `IntegrityError`. Catch
  `sqlite3.Error`.

## `tempfile`: temporary files and directories

`NamedTemporaryFile(suffix=, prefix=, dir=, delete=False)`, `mkdtemp(suffix=,
prefix=, dir=)` and `gettempdir()`.

```python
import tempfile
import os

d = tempfile.mkdtemp(prefix="run-", dir=".")
f = tempfile.NamedTemporaryFile(suffix=".csv", prefix="data-", dir=d, delete=False)
f.close()
print(os.path.isdir(d), oct(os.stat(d).st_mode & 0o777))
print(os.path.basename(f.name).startswith("data-"), f.name.endswith(".csv"), os.path.getsize(f.name))
```

```text
True 0o700
True True 0
```

CPython prints the same.

Where it differs from CPython:

- `NamedTemporaryFile` creates the file, empty, and closes it at once. What
  you get back is its name (`f.name`), not an open file. Open it by name to
  write to it.
- `delete=True` is refused at run time: the program stops with `Unhandled
  exception: Exception: tempfile.NamedTemporaryFile(delete=True) is not
  supported ...`. That is CPython's default, so pass `delete=False` and remove
  the file yourself.
- `gettempdir()` always returns `/tmp`. CPython returns `$TMPDIR` when it is
  set.
- `mkstemp`, `TemporaryFile`, `TemporaryDirectory` and `SpooledTemporaryFile`
  are not there.

## `re`: regular expressions for Nil Python

`match`, `search`, `fullmatch`, `findall`, `sub`, `subn`, `split`, `escape`
and `compile`, with the flags `re.I`, `re.X` and `re.S`. A match object has
`group`, `start` and `end`. The engine is the [`regex`](#regex-regular-expressions-for-pascal)
unit.

```python
import re

m = re.match(r"(\w+)-(\d+)", "item-42 rest")
print(m.group(0), m.group(1), m.group(2), m.start(2))
print(re.findall(r"\d+", "a1 b22 c333"))
print(re.sub(r"(\w+)@(\w+)", r"\2 at \1", "joe@home, ann@work"))
p = re.compile(r"colou?r", re.I)
print(p.findall("Color colour COLOR"))
print(re.split(r"[,;]\s*", "a, b;c"), re.escape("a.b*c"))
print(re.subn(r"o", "0", "foo boo"))
```

```text
item-42 item 42 5
['1', '22', '333']
home at joe, work at ann
['Color', 'colour', 'COLOR']
['a', 'b', 'c'] a\.b\*c
('f00 b00', 4)
```

CPython prints the same.

Where it differs from CPython, on v451:

- **A pattern the engine does not support matches nothing, silently.**
  Lookahead `(?=...)`, lookbehind `(?<=...)`, backreferences such as `\1`,
  named groups `(?P<name>...)` and possessive quantifiers such as `a++` make
  `re.search` return `None`, and `re.compile` does not raise. CPython matches
  them. To find out, ask the compiled pattern: `re.compile(r"foo(?=bar)").ok()`
  is `False` and `.error()` is `only (?:...) group extensions are supported`.
- With two or more groups, `findall` returns lists where CPython returns
  tuples: `re.findall(r"(\w)=(\d)", "a=1 b=2")` prints
  `[['a', '1'], ['b', '2']]`, CPython `[('a', '1'), ('b', '2')]`.

## `random` for Nil Python

`seed`, `random`, `randint`, `uniform`, `choice` and `shuffle`.

```python
import random

random.seed(7)
x = [1, 2, 3, 4]
random.shuffle(x)
print(sorted(x), 1 <= random.randint(1, 6) <= 6, 0 <= random.random() < 1)
print(random.choice("abc") in "abc", 1 <= random.uniform(1, 2) <= 2)
```

```text
[1, 2, 3, 4] True True
True True
```

CPython prints the same.

Where it differs from CPython, on v451:

- The numbers are not CPython's. After `random.seed(7)`, two `randint(1, 100)`
  calls give 88 and 5, CPython 42 and 20. A seeded sequence repeats from run
  to run, but a test that expects CPython's exact values fails.
- `random.sample` does not compile (`undefined variable (random)`).
- `random.seed(1)` returns 1; CPython returns `None`.
- `gauss`, `choices`, `randrange` and the other distributions were not
  checked for this entry.

## `collections`: `Counter` and `deque`

`Counter` (with `most_common`) and `deque`, imported by name.

```python
from collections import Counter, deque

c = Counter("abracadabra")
print(c.most_common(2))
d = deque([1, 2, 3])
d.appendleft(0)
d.append(4)
print(d.popleft(), d.pop(), len(d))
```

```text
[('a', 5), ('b', 2)]
0 4 3
```

CPython prints the same.

Where it differs from CPython, on v451:

- Only `from collections import ...` works. `import collections` followed by
  `collections.Counter(...)` does not compile.
- `OrderedDict`, `defaultdict` and `namedtuple` are not there. A plain `dict`
  keeps insertion order, as in CPython, and covers most uses of
  `OrderedDict`.

## `html`: escaping text for HTML

`html.escape(s, quote=True)` and `html.unescape(s)`.

```python
import html

s = "<a href=\"x\">Tom & 'Jerry'</a>"
print(html.escape(s))
print(html.escape(s, False))
print(html.unescape("&lt;b&gt; &amp; &quot;q&quot; &#39;s&#39; &#65;&#x42;"))
print(html.unescape("caf&eacute; &copy; &nbsp;x &bogus;"))
```

```text
&lt;a href=&quot;x&quot;&gt;Tom &amp; &#x27;Jerry&#x27;&lt;/a&gt;
&lt;a href="x"&gt;Tom &amp; 'Jerry'&lt;/a&gt;
<b> & "q" 's' AB
caf&eacute; &copy; &nbsp;x &bogus;
```

CPython prints the same first three lines. The difference is in the last
line: `unescape` knows the five entities `&lt;`, `&gt;`, `&amp;`, `&quot;` and
`&#39;` and every numeric form, and leaves other named entities as they are.
CPython prints `café © ` followed by a no-break space and `x &bogus;`.

## `markdown`: README-shaped Markdown to HTML

`markdown.markdown(text)` renders a subset: ATX headings (`#`), paragraphs,
fenced and indented code, flat unordered and ordered lists, blockquotes,
horizontal rules, and the inline forms for code, strong, emphasis, links and
bare URLs. The `extensions` argument is accepted. Of the extensions, `nl2br` works (a
line break becomes `<br />`) and the unit's source says `toc` adds heading
`id`s; the rest change nothing, and fenced code renders with or without
`fenced_code`.

````python
import markdown

text = """# Title

Some *emphasis*, **strong** and `code`, with [a link](https://example.org).

- one
- two

Para between.

1. first
2. second

> quoted

```
x = 1
```

---
"""
print(markdown.markdown(text, extensions=["fenced_code"]))
````

```text
<h1>Title</h1>
<p>Some <em>emphasis</em>, <strong>strong</strong> and <code>code</code>, with <a href="https://example.org">a link</a>.</p>
<ul>
<li>one</li>
<li>two</li>
</ul>
<p>Para between.</p>
<ol>
<li>first</li>
<li>second</li>
</ol>
<blockquote><p>quoted</p></blockquote>
<pre><code>x = 1
</code></pre>
<hr />
```

Python-Markdown 3.11 gives the same HTML, except that it puts the blockquote on
three lines (`<blockquote>`, `<p>quoted</p>`, `</blockquote>`); a browser
shows the two the same.

Where it differs from Python-Markdown:

- Tables, reference links (`[text][1]`) and setext headings (a line
  underlined with `===`) come out as literal text in a paragraph. A raw HTML
  block is escaped: `<div>raw</div>` shows as text, where Python-Markdown
  passes it through.
- A nested list is flattened: the inner item becomes a sibling of the outer
  one.
- A bulleted list followed directly by a numbered one, with no paragraph
  between, stays two lists. Python-Markdown merges them into one.

## `subprocess`: running other programs

`run`, `call` and `Popen` with `wait` and `poll`, and `subprocess.DEVNULL` for
`stdout`.

```python
import subprocess

r = subprocess.run(["/bin/sh", "-c", "exit 3"])
print("run:", r.returncode)
print("call:", subprocess.call(["/bin/true"]))
p = subprocess.Popen(["/bin/sh", "-c", "exit 5"])
print("wait:", p.wait())
p = subprocess.Popen(["/bin/sleep", "0.2"], stdout=subprocess.DEVNULL)
print("poll:", p.poll(), p.wait())
```

```text
run: 3
call: 0
wait: 5
poll: None 0
```

CPython prints the same.

Where it differs from CPython, on v451:

- **Give the program's full path.** The first item is not looked up in
  `PATH`: `subprocess.run(["sh", "-c", "exit 3"])` returns 127 and
  `subprocess.call(["true"])` returns 127, where CPython finds `/bin/sh` and
  `/bin/true` and returns 3 and 0.
- There is no way to read a child's output yet. `run` refuses
  `capture_output=`, `stdout=`, `shell=`, `check=` and `cwd=` when the program
  is compiled (`run has no parameter named ...`), `check_output` and
  `communicate` do not exist, and `Popen(..., stdout=subprocess.PIPE)` stops
  the program with `subprocess: stdout= is not supported yet (only DEVNULL or
  omitted)`.
- `stderr=subprocess.DEVNULL` is accepted but not honoured: the child's
  standard error still reaches the terminal.

## Next

- [Standard library](./index.md)
- [Nil Python](../targets/nil-python.md)
- [Known issues](../reference/known-issues.md)
