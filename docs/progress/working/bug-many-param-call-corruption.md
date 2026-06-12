# Self-hosted x86-64 backend miscompiles calls with many parameters

- **Type:** bug
- **Status:** working
- **Owner:** claude
- **Found / Opened:** 2026-06-12 (while writing writeELF32Rel, feature-elf-rel-writer)

## Symptom

Calls to procedures with ~7+ integer parameters silently corrupt the
arguments **only when compiled by the self-hosted compiler**; the FPC-built
compiler generates correct code for the same source. The callee receives
shifted argument values (e.g. param 1 receives the value of param 4/5), so a
file descriptor passed as the first argument arrived as a junk integer and
every `syswrite` failed with EBADF — the output file was silently truncated.

The exact trigger is some interaction of parameter count, locals, and calls
inside the callee body — not parameter count alone:

- 10 params, body only uses `writeln`: **works**
- 10 params, body calls another 2-param proc: **broken** (arg shift)
- 9 params, no locals, body calls another proc: **works**
- 9 params, one local var, body calls another proc: **broken**

## Repro

```pascal
program P9c;
var sysbuf2: array[0..7] of Byte;
procedure wU32(f: Integer; v: Integer);
var n: Integer;
begin
  sysbuf2[0] := v and 255;
  n := syswrite(f, sysbuf2, 4);
  writeln('wrote ', n, ' fd ', f, ' v ', v);
end;
procedure wShdr(f: Integer; name, typ, flags, off, size, link, info, alignv: Integer);
var entsize: Integer;
begin
  entsize := 0;
  if typ = 4 then entsize := 12;
  wU32(f, name); wU32(f, entsize); wU32(f, alignv);
end;
var f: Integer; p: AnsiString;
begin
  p := '/tmp/p9c.bin';
  f := sysopen(p, 577);
  writeln('fd=', f);
  wShdr(f, 7, 4, 64, 100, 200, 6, 1, 4);
end.
```

Compiled with the self-hosted `compiler/pascal26`, prints
`wrote -9 fd 64 v 100` — f received arg #4 (64), name received arg #5 (100).
Compiled with the FPC-built compiler, prints `wrote 4 fd 3 v 7`.

## Impact / workaround

The compiler source itself avoids the shape (checked: suite + self-host
fixpoint green), but it is a silent wrong-code landmine for user programs
and future compiler code. `writeELF32Rel` works around it by splitting the
section-header writer into two <=6-parameter helpers (`writeShdrA`/`B`) —
see the comment in `compiler/elfwriter.inc`.

Suspect area: x86-64 IR_CALL argument staging vs. prologue spill offsets
when args exceed the register-arg budget (stack-spill path), possibly
clobbered by the callee's own frame/local layout.

## Acceptance

- Repro above prints `fd 3` for all wU32 calls when compiled self-hosted.
- A `make test` case with 8/9/10-param procs (with locals and nested calls)
  comparing self-hosted output against FPC-built output.
- Self-host fixpoint and full suite stay green.

## Log
- 2026-06-12 — found while implementing the ET_REL writer: 9/10-param shdr
  helper produced a truncated .o (section headers never written because the
  fd argument arrived corrupted and writes failed silently). Bisected to the
  call shape, not the writer.
