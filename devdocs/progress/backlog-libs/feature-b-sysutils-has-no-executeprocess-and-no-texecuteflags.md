---
slug: feature-b-sysutils-has-no-executeprocess-and-no-texecuteflags
title: "`sysutils` declares neither `TExecuteProcess` nor `TExecuteFlags`, and it is the FPC-compiler-source march's current wall"
track: B
prio: 40
type: feature
status: backlog
owner: unassigned
created: 2026-09-09
found-by: frankH
blocked-by: []
summary: "`lib/rtl/sysutils.pas` has no `ExecuteProcess` and no `TExecuteFlags` — `grep -rn TExecuteFlags lib/rtl/ compiler/builtin/` is empty. FPC's `cfileutl.pas` declares two `RequotedExecuteProcess` overloads with `Flags: TExecuteFlags = []`, so the FPC-compiler-source march stops at `cfileutl.pas:136 unknown type: TExecuteFlags`. Not a parser bug: the same shape (a defaulted set parameter after an open-array parameter, both overloads) compiles standalone. The primitive already exists — `PalVforkAndExec`, which `lib/rtl/subprocess.pas` builds `Popen` on — so this is a sysutils surface over machinery that is already here, not new capability."
---

# The wall, and how to stand in front of it

```
$ pascal26 --mimic-fpc-compiler \
    -Fu/usr/share/fpcsrc/3.2.2/compiler \
    -Fu/usr/share/fpcsrc/3.2.2/compiler/x86_64 cf.pas
pascal26:136: error: unknown type: TExecuteFlags
  in: /usr/share/fpcsrc/3.2.2/compiler/cfileutl.pas
  near: ComLine : AnsiString ; Flags : >>> TExecuteFlags = [
pascal26:137: error: unknown type: TExecuteFlags
```

`cf.pas` is `program cf; uses comphook, finput, cfileutl; begin WriteLn('cf ok') end.`
The second `-Fu` is not optional — without it `cpuinfo` is not found first and
you never reach this. **Writing the configuration down is the point of this
ticket**: the march is driven by hand, and frankB's standing note is that *"a
substitute for a flag is a configuration nobody else runs, so every number it
produces is unshared."*

# What it is NOT

The parse is fine. Two overloads with a defaulted set after an open-array
parameter compile and run:

```pascal
type TEF = set of (efInheritsHandles);
function A(const P: AnsiString; const C: AnsiString;       F: TEF = []): LongInt;
function B(const P: AnsiString; const C: array of AnsiString; F: TEF = []): LongInt;
```
prints `1 2`. The type is simply absent from our RTL.

# What FPC declares

`rtl/objpas/sysutils/sysutilh.inc`:

```pascal
type
  TExecuteFlags = set of (ExecInheritsHandles);
function ExecuteProcess(const Path, ComLine: AnsiString; Flags: TExecuteFlags = []): Integer;
function ExecuteProcess(const Path: AnsiString; const ComLine: array of AnsiString;
                        Flags: TExecuteFlags = []): Integer;
```
plus `RawByteString`/`UnicodeString` spellings and `EOSError`.

# The machinery is already here

`lib/rtl/subprocess.pas:102` builds `Popen` on `PalVforkAndExec(prog, argvp,
envp, ...)` and waits with `Popen.wait`. `ExecuteProcess` is the same three
steps with a different argument shape — split `ComLine` on whitespace for the
string overload, take the array directly for the other. **A type-only stub is
worse than nothing**: `cfileutl`'s implementation section calls
`ExecuteProcess`, so parsing further only moves the failure to link time.

# Where it came from

The march's previous wall, `cclasses.pas:2909`, is gone — see
[[bug-p-a-double-deref-in-fpcs-cclasses-is-refused-and-the-obvious-reduction-compiles]],
attributed to `a4cbaa1de`. Four walls have now fallen in this unit in sequence
(`TFPCHeapStatus`, the forward pointer-to-array, `Prefetch`, the double deref);
each was invisible until the one in front of it cleared, which is why a march
wall is worth a ticket only once it is the frontier.
