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

Modules for Nil Python:

- [`configparser`](#configparser-ini-files): INI settings files.
- [`pathlib`](#pathlib-paths-as-objects): paths as objects.
- [`urllib.parse`](#urllibparse-splitting-a-url): splitting and quoting URLs.
- [`sqlite3`](#sqlite3-the-db-api-over-the-system-library): SQLite through Python's DB-API.

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

## Next

- [Standard library](./index.md)
- [Nil Python](../targets/nil-python.md)
- [Known issues](../reference/known-issues.md)
