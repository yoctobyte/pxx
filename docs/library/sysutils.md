---
title: SysUtils
order: 52
---

# Standard Utilities — the `sysutils` unit

The `sysutils` unit implements FPC-compatible standard utility routines for string conversion, path manipulation, process execution, and memory operations. Almost every non-trivial Pascal program imports this unit.

---

## Exception Class

The `sysutils` unit defines the base `Exception` class used by the PXX exception handling system.

```pascal
type
  Exception = class
  private
    FMessage: string;
    FHelpContext: Integer;
  public
    constructor Create(const msg: string);
    property Message: string read FMessage write FMessage;
    property HelpContext: Integer read FHelpContext write FHelpContext;
  end;
```

---

## Conversions and Formatting

### Integer Conversions
- **`function IntToStr(value: Int64): AnsiString;`**
  Converts an integer to its decimal string representation (handles negative numbers).
- **`function IntToHex(value: Int64; digits: Integer): AnsiString;`**
  Converts an integer to its uppercase hexadecimal string representation, left-zero-padded to at least `digits` characters. Negative values use their two's-complement bits.
- **`function StrToInt(const s: AnsiString): Integer;`**
  Parses a decimal integer string. Returns `0` on malformed input.
- **`function StrToIntDef(const s: AnsiString; def: Integer): Integer;`**
  Parses a decimal integer string. Returns `def` if parsing fails.
- **`function TryStrToInt(const s: AnsiString; var value: Integer): Boolean;`**
  Attempts to parse a decimal integer string. Returns `True` and updates `value` on success; returns `False` on failure.

### Floating-Point Conversions
- **`function FloatToStr(value: Double): AnsiString;`**
  Converts a floating-point number to a compact string representation.
- **`function FloatToStrF(value: Double; precision: Integer): AnsiString;`**
  Converts a floating-point number to a fixed-point string with `precision` digits after the decimal point.
- **`function StrToFloat(const s: AnsiString): Double;`**
  Parses a floating-point string. Returns `0.0` on malformed input.
- **`function StrToFloatDef(const s: AnsiString; def: Double): Double;`**
  Parses a floating-point string. Returns `def` if parsing fails.

### String Formatting
- **`function Format(const fmt: AnsiString; const args: array of const): AnsiString;`**
  Formulate a string using printf-style specifiers over an open array of constants. Supported specifiers:
  - `%d` / `%u`: Signed / unsigned decimal integer.
  - `%x`: Hexadecimal integer.
  - `%s`: String.
  - `%f` / `%g`: Floating-point formats.
  - `%c`: Character.
  - `%%`: Literal percent sign.
  - Supports width, `-` (left-alignment), `0` (zero-padding), and `.precision` flags.

---

## String Manipulation

- **`function Trim(const s: AnsiString): AnsiString;`**
  Strips control characters and spaces (characters $\le$ `' '`) from both ends.
- **`function TrimLeft(const s: AnsiString): AnsiString;`**
  Strips control characters and spaces from the left end.
- **`function TrimRight(const s: AnsiString): AnsiString;`**
  Strips control characters and spaces from the right end.
- **`function UpperCase(const s: AnsiString): AnsiString;`**
  Converts an ASCII string to uppercase.
- **`function LowerCase(const s: AnsiString): AnsiString;`**
  Converts an ASCII string to lowercase.
- **`function UpCase(c: Char): Char;`**
  Converts a single ASCII character to uppercase.
- **`function Pos(const substr, s: AnsiString): Integer;`**
  Returns the 1-based index of the first occurrence of `substr` in `s`, or `0` if not found.
- **`function StringReplace(const S, OldPattern, NewPattern: AnsiString; Flags: TReplaceFlags): AnsiString;`**
  Replaces occurrences of `OldPattern` in `S` with `NewPattern`. `Flags` is a set containing:
  - `rfReplaceAll`: Replace all occurrences (default is first occurrence only).
  - `rfIgnoreCase`: Case-insensitive matching.
- **`function CompareStr(const s1, s2: AnsiString): Integer;`**
  Performs a case-sensitive, byte-by-byte lexicographical comparison of `s1` and `s2`. Returns $<0$ if $s1 < s2$, $0$ if $s1 = s2$, or $>0$ if $s1 > s2$.
- **`function CompareText(const s1, s2: AnsiString): Integer;`**
  Performs a case-insensitive, byte-by-byte comparison of `s1` and `s2`.
- **`function SameText(const s1, s2: AnsiString): Boolean;`**
  Returns `True` if `s1` and `s2` are case-insensitively equal.
- **`function StringOfChar(ch: Char; count: Integer): AnsiString;`**
  Returns a string containing `count` copies of `ch`.
- **`function PadLeft(const s: AnsiString; len: Integer; ch: Char): AnsiString;`**
  Left-pads `s` to a total length of `len` characters using `ch`.
- **`function PadRight(const s: AnsiString; len: Integer; ch: Char): AnsiString;`**
  Right-pads `s` to a total length of `len` characters using `ch`.
- **`function QuotedStr(const s: AnsiString): AnsiString;`**
  Wraps `s` in single quotes, doubling any embedded single quotes.
- **`procedure Delete(var s: AnsiString; index, count: Integer);`**
  Removes `count` characters from `s` starting at the 1-based `index`.
- **`procedure Insert(const src: AnsiString; var dst: AnsiString; index: Integer);`**
  Inserts `src` into `dst` at the 1-based `index`.

---

## File System and Path Helpers

- **`function ExtractFileName(const path: AnsiString): AnsiString;`**
  Extracts the filename portion after the last path separator.
- **`function ExtractFilePath(const path: AnsiString): AnsiString;`**
  Extracts the path up to and including the last path separator.
- **`function ExtractFileDir(const path: AnsiString): AnsiString;`**
  Extracts the directory path up to but excluding the last path separator.
- **`function ExtractFileExt(const path: AnsiString): AnsiString;`**
  Extracts the file extension, including the dot (e.g., `'.exe'`).
- **`function ChangeFileExt(const path, ext: AnsiString): AnsiString;`**
  Changes the file extension of `path` to `ext`.
- **`function IncludeTrailingPathDelimiter(const path: AnsiString): AnsiString;`**
  Appends a path separator to the end of `path` if it does not already end with one.
- **`function ExcludeTrailingPathDelimiter(const path: AnsiString): AnsiString;`**
  Removes a trailing path separator from the end of `path`.
- **`function GetDirectoryContents(const path: AnsiString; var list: TFileInfoArray): Boolean;`**
  Lists all files and directories under `path` (excluding `.` and `..`). Fills a `TFileInfoArray` with metadata. Returns `True` on success.

---

## Process and System Primitives

- **`function ExecutePipeline(const cmd: AnsiString; const args: array of AnsiString; var childStdinFd, childStdoutFd: Integer): Integer;`**
  Executes an external process in a pipeline, returning its PID and redirecting standard input/output via socket pipes if requested.
- **`procedure Sleep(Milliseconds: Cardinal);`**
  Suspends the current thread for at least the specified duration (backed by POSIX `nanosleep`).

---

## Low-Level Memory Helpers

- **`procedure Move(const Source; var Dest; Count: Integer);`**
  Copies `Count` bytes from `Source` to `Dest`. This is overlap-safe (equivalent to `memmove` semantics).
- **`procedure FillChar(var X; Count: Integer; Value: Byte);`**
  Fills a memory buffer `X` with `Count` copies of the byte `Value`.

---

## Compiling Example

The following program demonstrates formatting, string conversions, string manipulation, and path helpers. It compiles and runs on the pinned compiler:

```pascal
program sysutils_demo;

uses sysutils;

procedure DemoFormatting;
var
  s: AnsiString;
begin
  writeln('--- Formatting & Conversions ---');
  writeln('IntToStr: ', IntToStr(42));
  writeln('IntToHex: ', IntToHex(255, 4));
  writeln('FloatToStr: ', FloatToStr(3.14159));
  writeln('FloatToStrF: ', FloatToStrF(3.14159, 2));
  
  // Format with array of const
  s := Format('Hello %s, the answer is %d, float is %.2f', ['PXX', 42, 3.14159]);
  writeln('Format: ', s);
end;

procedure DemoStrings;
var
  s: AnsiString;
begin
  writeln('--- String Manipulation ---');
  s := '  PXX Compiler  ';
  writeln('Trimmed: "', Trim(s), '"');
  writeln('Upper: ', UpperCase(s));
  writeln('Lower: ', LowerCase(s));
  writeln('Pos of "Comp": ', Pos('Comp', s));
  
  // StringReplace
  s := 'apple, banana, apple';
  writeln('Replace: ', StringReplace(s, 'apple', 'orange', [rfReplaceAll]));
end;

procedure DemoPaths;
var
  path: AnsiString;
begin
  writeln('--- Path Helpers ---');
  path := '/usr/local/bin/pxx.exe';
  writeln('FileName: ', ExtractFileName(path));
  writeln('FilePath: ', ExtractFilePath(path));
  writeln('FileDir:  ', ExtractFileDir(path));
  writeln('FileExt:  ', ExtractFileExt(path));
  writeln('ChangeExt: ', ChangeFileExt(path, '.o'));
end;

begin
  DemoFormatting;
  DemoStrings;
  DemoPaths;
end.
```

### Output

```
--- Formatting & Conversions ---
IntToStr: 42
IntToHex: 00FF
FloatToStr: 3.14159
FloatToStrF: 3.14
Format: Hello PXX, the answer is 42, float is 3.14
--- String Manipulation ---
Trimmed: "PXX Compiler"
Upper:   PXX COMPILER  
Lower:   pxx compiler  
Pos of "Comp": 7
Replace: orange, banana, orange
--- Path Helpers ---
FileName: pxx.exe
FilePath: /usr/local/bin/
FileDir:  /usr/local/bin
FileExt:  .exe
ChangeExt: /usr/local/bin/pxx.o
```

---

## Next

- [Core classes (Lists & Streams)](./core.md)
- [Networking (HTTP / HTTPS)](./networking.md)
- [Back to the standard library reference](./index.md)
