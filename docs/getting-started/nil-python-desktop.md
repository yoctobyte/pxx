---
title: Nil Python on the desktop
order: 24
---

# Nil Python on the desktop

Nil Python is Python compiled ahead of time to machine code. The same
compiler that builds Pascal and C builds it, and there is no interpreter at
run time: `./pxx prog.npy prog` writes a static Linux executable, as it does for
a `.pas` file. This page runs a few ordinary Python programs on a PC. For the
ESP32, where Nil Python gets MicroPython's module names, start with
[Coming from MicroPython](./from-micropython.md) instead.

**What was checked.** Every program on this page was cut from this page and
built with [pin](../reference/glossary.md#terms-in-the-release-notes-and-the-esp-pages) v450 (compiler sha256 `c19cc2d531e4`) from the
v0.1.0-beta.1 release tarball, after `./install.sh --yes`, on x86-64 Linux on
2026-09-29. Each output block is what the program printed. For the first three
programs, CPython 3.14.4 printed the same bytes.

## Hello

`hello.npy` (`hello.py` works too; the extension picks the frontend):

```python
print("Hello, world!")
```

```sh
./pxx hello.npy hello
./hello
```

```text
Hello, world!
```

## Functions, a class, a list and a dict

`shop.npy`:

```python
class Item:
    def __init__(self, name, price, qty):
        self.name = name
        self.price = price
        self.qty = qty

    def total(self):
        return self.price * self.qty


def totals_by_name(items):
    totals = {}
    for it in items:
        totals[it.name] = it.total()
    return totals


items = [Item("apple", 0.5, 6), Item("pear", 0.75, 4), Item("fig", 2.0, 1)]
totals = totals_by_name(items)
for name in sorted(totals):
    print(f"{name:6s} {totals[name]:5.2f}")
print("sum", sum(totals.values()))
print("most", max(totals, key=totals.get))
```

```sh
./pxx shop.npy shop
./shop
```

```text
apple   3.00
fig     2.00
pear    3.00
sum 8.0
most apple
```

## Files and the standard library

`json` and `os.path` import as in CPython. `config.npy` writes a JSON file,
checks it, and reads it back:

```python
import json
import os.path

data = {"name": "pxx", "targets": ["x86-64", "aarch64"], "beta": 1}
with open("config.json", "w") as f:
    json.dump(data, f)

print(os.path.exists("config.json"), os.path.getsize("config.json"))
with open("config.json") as f:
    back = json.load(f)
print(back["name"], len(back["targets"]), back == data)
```

```text
True 60
pxx 2 True
```

The `config.json` it writes is byte for byte the one CPython writes.

## Calling Pascal from Python

A Pascal unit is imported by quoting its file name and giving it an alias.
With a path (`./mathx.pas`) the file is found next to the program; with a bare
name (`sysutils.pas`) it is found on the unit search path, which is how the
Pascal runtime's own units are reached. `mathx.pas`:

```pascal
unit mathx;
{$mode objfpc}{$H+}

interface

function Gcd(A, B: Integer): Integer;
function Shout(const S: string): string;

implementation

uses SysUtils;

function Gcd(A, B: Integer): Integer;
var T: Integer;
begin
  while B <> 0 do
  begin
    T := A mod B;
    A := B;
    B := T;
  end;
  Result := A;
end;

function Shout(const S: string): string;
begin
  Result := UpperCase(S) + '!';
end;

end.
```

`usepas.npy`, in the same directory:

```python
import './mathx.pas' as mx
import 'sysutils.pas' as su

print(mx.Gcd(84, 36))
print(mx.Shout("hello from pascal"))
print(su.Trim("   trimmed   ") + "|")
```

```sh
./pxx usepas.npy usepas
./usepas
```

```text
12
HELLO FROM PASCAL!
trimmed|
```

There is no binding code to write: the Python call reaches the Pascal
function directly. CPython does not accept the quoted import, which is Nil
Python's own. More on imports, including C headers, is in
[Nil Python: Imports](../targets/nil-python.md#imports).

## Another CPU

`--target=` builds for i386, aarch64 or arm32 as it does for Pascal, and
`tools/run_target.sh` runs the result under QEMU user mode:

```sh
./pxx --target=aarch64 shop.npy shop.a64
tools/run_target.sh aarch64 ./shop.a64
```

This printed the same five lines as on x86-64, and so did
`--target=riscv32` under `tools/run_target.sh riscv32`: riscv32 Linux takes
Nil Python from v450 (`d07cbfbb40`), and refused it before.

With v450 itself, `os.path.getsize` and `os.stat(...).st_size` read 0 on
i386, aarch64 and arm32, so `config.npy` prints `True 0` there. That is
fixed after v450 (`822df4c6ad`), where the same program prints `True 60`
on aarch64 and arm32.

## What is different from CPython

Nil Python follows CPython's syntax and semantics, but it is compiled, and
some things differ on purpose:

- Imports are resolved when you build, so `sys.path` changes do nothing at
  run time; use `-Fu`.
- `exec` and `eval` run a subset of Python, and see only the namespace you
  pass them.
- There is no garbage collector: an object is freed when its last reference
  goes, so objects that refer only to each other are never freed.

The full list is in [Nil Python](../targets/nil-python.md), under
[Where it differs on purpose](../targets/nil-python.md#where-it-differs-on-purpose)
and [Known limits](../targets/nil-python.md#known-limits). Problems that are
not deliberate are on [Known issues](../reference/known-issues.md#nil-python).
Nil Python is best effort in this beta: a program that uses the shapes above is
on well-tested ground.
