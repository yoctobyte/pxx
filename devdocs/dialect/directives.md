# Directives & switches

## Source directives

| Directive | Default | Effect |
| --- | --- | --- |
| `{$NESTEDCOMMENTS ON\|OFF}` | **on** (off under `{$mode delphi}`) | Nest `{ }` and `(* *)` — real FPC default (verified 3.2.2); a lone `{` inside a brace comment opens a level, so `{ consume '{' }` is NOT legal FPC/pxx. |
| `{$CSTYLECOMMENTS ON\|OFF}` | off | Recognize `/* … */`. |
| `{$CASESENSITIVE ON\|OFF}` | off | Case-sensitive identifiers in this source. |
| `{$LAZYCASING ON\|OFF}` | off | Allow a wrong-case call to a C-import (`external`) routine to resolve when exactly one matches case-insensitively (warns; ambiguous = error). |
| `{$STRICT_OVERLOAD ON\|OFF}` | off | Require `overload;` on every overloaded variant. |
| `{$THREADSAFE ON\|OFF}` | off | Atomic refcounts for managed strings/arrays. |
| `{$PACKRECORDS N}` / `{$ALIGN N}` | 8 | Record field alignment (`1`/`2`/`4`/`8`/`16`/`normal`). |
| `{$R name}` / `{$R *.lfm}` | — | Queue an embedded resource (`*` = current unit base). |
| `{$asmMode intel}` | — | Intel syntax marker for an asm block. |

`{$mode objfpc}` / `-Mobjfpc` are accepted markers, not full mode emulation.
Unknown directives are accepted as comments.

C-import (`external`) routine names are matched **case-sensitively** by default —
a C linker symbol `add_two` is not the same as `Add_Two`. A wrong-case call is an
error unless `{$LAZYCASING ON}` is in effect. Ordinary Pascal routines stay
case-insensitive (unless `{$CASESENSITIVE ON}`).

## Conditional compilation

Supported: `{$define}` / `{$undef}`, `{$ifdef}` / `{$ifndef}` / `{$else}` /
`{$endif}`, and `{$if}` / `{$elseif}` over a small expression subset —
`defined(NAME)`, bare symbols, `not`/`and`/`or`, parentheses, `0`/`1`.
`{$include}` is one level deep, active branches only. `{$warning}` /
`{$message}` / `{$error}` fire in active branches.

**Valued defines and macro replacement are not implemented** — a define is just
present/absent.

See [Targets](targets.md) for the predefined symbols (`PXX`, `LINUX`, the
`CPU…` set, `PXX_MANAGED_STRING`). `PXX` cannot be undefined; `{$ifdef FPC}` is
always false under PXX.

## Command-line switches

The full list is in [Command Line](../cli.md). The dialect-affecting ones:

| Flag | Effect |
| --- | --- |
| `--target=ARCH` | Cross-compile (see [Targets](targets.md)). |
| `-dNAME` / `-uNAME` | Define / undefine a symbol (`PXX` cannot be undefined). |
| `-uPXX_MANAGED_STRING` | Select the frozen string ABI (managed is the default). |
| `--strict-overload` / `--permissive-overload` | Toggle the `overload;` requirement. |
| `-Werror` / `--werror` | Promote any compiler warning to a fatal error. |
| `--threadsafe` | Atomic refcounts (same as `{$THREADSAFE ON}`). |
| `--no-auto-var` / `--no-lazy-var` | Disable auto-typed / inline `var`. |
| `--dump-ir` / `--dump-rtti` | Print IR / RTTI while still emitting the executable. |
| `--no-unhandled-handler` | Unhandled exception exits status 1 silently. |
