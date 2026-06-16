# Directives & switches

## Source directives

| Directive | Default | Effect |
| --- | --- | --- |
| `{$NESTEDCOMMENTS ON\|OFF}` | off | Nest `{ }` and `(* *)`. |
| `{$CSTYLECOMMENTS ON\|OFF}` | off | Recognize `/* … */`. |
| `{$CASESENSITIVE ON\|OFF}` | off | Case-sensitive identifiers in this source. |
| `{$STRICT_OVERLOAD ON\|OFF}` | off | Require `overload;` on every overloaded variant. |
| `{$THREADSAFE ON\|OFF}` | off | Atomic refcounts for managed strings/arrays. |
| `{$PACKRECORDS N}` / `{$ALIGN N}` | 8 | Record field alignment (`1`/`2`/`4`/`8`/`16`/`normal`). |
| `{$R name}` / `{$R *.lfm}` | — | Queue an embedded resource (`*` = current unit base). |
| `{$asmMode intel}` | — | Intel syntax marker for an asm block. |

`{$mode objfpc}` / `-Mobjfpc` are accepted markers, not full mode emulation.
Unknown directives are accepted as comments.

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
| `--threadsafe` | Atomic refcounts (same as `{$THREADSAFE ON}`). |
| `--no-auto-var` / `--no-lazy-var` | Disable auto-typed / inline `var`. |
| `--dump-ir` / `--dump-rtti` | Print IR / RTTI while still emitting the executable. |
| `--no-unhandled-handler` | Unhandled exception exits status 1 silently. |
