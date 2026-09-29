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

Modules for Nil Python:

- [`configparser`](#configparser-ini-files): INI settings files.
- [`pathlib`](#pathlib-paths-as-objects): paths as objects.
- [`urllib.parse`](#urllibparse-splitting-a-url): splitting and quoting URLs.
- [`sqlite3`](#sqlite3-the-db-api-over-the-system-library): SQLite through Python's DB-API.
- [`tempfile`](#tempfile-temporary-files-and-directories): temporary files and directories.

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

## Next

- [Standard library](./index.md)
- [Nil Python](../targets/nil-python.md)
- [Known issues](../reference/known-issues.md)
