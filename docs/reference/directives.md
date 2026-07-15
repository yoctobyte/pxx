---
title: Compiler directives
order: 94
---

# Compiler directives

Directives are `{$...}` comments the compiler reads while lexing. This page
lists the directives PXX recognizes. Anything not listed here is accepted as an
inert comment (so FPC sources with unsupported directives still compile), which
means a misspelled directive is silently ignored rather than flagged.

Where a directive has an equivalent [command-line flag](./cli.md), it is named
in the table. The strictness switches are explained in context on the
[compiler modes](./modes.md) page.

## Conditional compilation

| Directive | Effect |
| --- | --- |
| `{$DEFINE name}` | Define a conditional symbol (optionally `{$DEFINE name := value}`). |
| `{$UNDEF name}` | Undefine a conditional symbol. |
| `{$IFDEF name}` | Compile the branch if `name` is defined. |
| `{$IFNDEF name}` | Compile the branch if `name` is not defined. |
| `{$IF expr}` | Compile the branch if `expr` is true (see below). |
| `{$IFOPT x}` | Compile-option test. Option switches are not modelled, so the branch is always taken as false. |
| `{$ELSEIF expr}` | `else`-branch guarded by `expr`, only if no prior branch was taken. |
| `{$ELSE}` | Compile the branch if no prior branch in the chain was taken. |
| `{$ENDIF}` / `{$IFEND}` | Close the conditional. |

`{$IF}` / `{$ELSEIF}` expressions support `defined(NAME)`, `declared(NAME)`,
integer literals and defined integer symbols, the comparison operators, `!`
(not), and parentheses. A bare non-zero integer is true (`{$IF 1}` / `{$IF 0}`).
Float literals are rejected.

## Includes and resources

| Directive | Effect | Flag |
| --- | --- | --- |
| `{$I file}` / `{$INCLUDE file}` | Include another source file. Search roots come from `-Fi` / `-I`. (A leading `+`/`-` selects the IO-check switch below instead.) | `-Fi`, `-I` |
| `{$R file}` / `{$R name file}` | Queue an embedded resource. `{$R *.lfm}` resolves the wildcard to the current unit; a `.res` file is a no-op. (A leading `+`/`-` selects the range-check switch below.) | |

## Check switches

Short toggles use a trailing `+` (on) or `-` (off); the long forms take
`ON` / `OFF`.

| Directive | Effect | Default | Flag |
| --- | --- | --- | --- |
| `{$I+}` / `{$I-}` · `{$IOCHECKS ON\|OFF}` | IO-result checking after file operations. | On | |
| `{$R+}` / `{$R-}` · `{$RANGECHECKS ON\|OFF}` | Range checking. | Off | |
| `{$Q+}` / `{$Q-}` · `{$OVERFLOWCHECKS ON\|OFF}` | Integer overflow checking. | Off | |

## Strictness and dialect switches

Each takes `ON` / `OFF` and has a matching command-line flag — see
[compiler modes](./modes.md).

| Directive | Effect | Default | Flag |
| --- | --- | --- | --- |
| `{$STRICT ON\|OFF}` | FPC-parity strictness umbrella (routine visibility). | Off | `--strict` |
| `{$STRICT_OVERLOAD ON\|OFF}` | Require explicit `overload;`. | Off | `--strict-overload` |
| `{$STRICT_OPERATOR ON\|OFF}` | Reject `=` / `<>` on class operands. | Off | `--strict-operator` |
| `{$STRICT_CASE ON\|OFF}` | Inverted-range / duplicate `case`-label diagnostics. | Off | `--strict-case` |
| `{$STRICT_VISIBILITY ON\|OFF}` | Enforce member visibility. | Off | `--strict-visibility` |
| `{$STRICT_FPC ON\|OFF}` | FPC-parity umbrella: case + operator + visibility + require-forward (not overload). | Off | `--strict-fpc` |
| `{$DECLORDER ON\|OFF}` | Declare-before-use for forward-visible globals. `OFF` = lax. | On | `--lax-decl-order` (opt-out) |
| `{$IMPLICITVARS ON\|OFF}` | Undeclared assignment declares an inferred-type local. | Off | `--auto-locals` |
| `{$MIMIC FPC}` | FPC-compatibility preset: `{$STRICT_FPC}` + FPC defines + `{$I+}`. | — | `--mimic-fpc` |

## Layout, comments, and dialect

| Directive | Effect | Default |
| --- | --- | --- |
| `{$mode delphi\|objfpc\|fpc\|tp\|macpas}` | Only `delphi` changes behavior (the `@`-optional procedural value, and no nested comments); the others are accepted but inert. | (no marker) |
| `{$PACKRECORDS N}` / `{$ALIGN N}` | Record field alignment: `normal`/`default` or `1`/`2`/`4`/`8`/`16`. | 8 |
| `{$SCOPEDENUMS ON\|OFF}` | Enum members live only under the type scope (`TEnum.member`). | Off |
| `{$NESTEDCOMMENTS ON\|OFF}` | Allow nested same-type comments. | On |
| `{$CSTYLECOMMENTS ON\|OFF}` | Accept `/* … */` comments. | Off |
| `{$CASESENSITIVE ON\|OFF}` | Case-sensitive identifiers. | Off |
| `{$LAZYCASING ON\|OFF}` | Relaxed identifier casing. | Off |
| `{$INTERFACES COM\|CORBA}` | Interface model: COM (refcounted) or CORBA (unmanaged). | COM |
| `{$ASMMODE intel\|att}` | Inline-asm syntax. Intel only; `att` is an error. | intel |

## Runtime knobs and messages

| Directive | Effect | Flag |
| --- | --- | --- |
| `{$THREADSAFE ON\|OFF}` | Atomic managed-refcount runtime (x86-64/i386/aarch64/arm32; on i386/aarch64/arm32 use the `--threadsafe` flag instead). | `--threadsafe` |
| `{$FASTDOUBLES ON\|OFF}` | Compute `Double` via the hardware single FPU where present (lossy; xtensa only, no-op elsewhere). | |
| `{$MAXSTACKFRAME n}` / `{$MAXSTACKFRAME OFF}` | Oversized-stack-frame warning threshold in bytes. | `--max-stack-frame=` |
| `{$WARNING text}` | Emit a compile-time warning. | |
| `{$MESSAGE text}` | Emit a compile-time message. | |
| `{$ERROR text}` | Emit a compile-time error and stop. | |

## Next

- [Command line](./cli.md)
- [Compiler modes and strictness](./modes.md)
- [FPC compatibility](../language/fpc-compatibility.md)
