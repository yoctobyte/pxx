---
title: Command line
order: 91
---

# Command line

The installed wrapper is normally called as:

```sh
pxx [options] source [output]
```

From a checkout, use:

```sh
./pxx [options] source [output]
```

The wrapper created by `install.sh` calls the pinned compiler and adds bundled
library roots. The underlying compiler executable is still named
`compiler/pascal26`.

## Source and output

With an output path, PXX writes the executable there and emits a matching map
file. Without an output path, it derives one from the source name and refuses to
overwrite the source.

An output path ending in `.o` also selects object-output mode, the same as
passing `--emit-obj`. An output path ending in `.so` selects shared-library
mode, the same as passing `--shared`.

## Options

| Option | Effect |
| --- | --- |
| `--target=ARCH` | Select `x86_64`, `i386`, `aarch64`, `arm32`, `riscv32`, or `xtensa`. |
| `--xtensa-abi=call0\|windowed` | Select the Xtensa call ABI. |
| `--xtensa-cpu=lx6` | Use the older ESP32 LX6 software divide/mod profile. |
| `--xtensa-fpu` | Use Xtensa hardware single-precision float operations where supported. |
| `--esp-profile=bare` | Select the bare-metal ESP platform profile for `riscv32` or `xtensa`. |
| `--emit-obj` | Emit a relocatable object (`.o`) instead of a linked executable, on any target. Same as an output path ending in `.o`. |
| `--shared` | Emit an ET_DYN shared library (`.so`) instead of an executable. x86-64 only; introduced for and validated with the `.asm` assembly-source frontend. Same as an output path ending in `.so`. |
| `-S` | Also write `<output>.s`, a best-effort x86-64 disassembly text dump of the emitted code. Additive — the normal output (executable, `--emit-obj`, or `--shared`) still happens. x86-64 only. |
| `-g` | Emit DWARF debug information. |
| `--debug` | Print compiler tracing diagnostics. |
| `--dump-ir` | Print lowered IR while still emitting output. |
| `--dump-rtti` | Print generated RTTI tables while still emitting output. |
| `-dNAME` | Define a conditional compilation symbol. |
| `-uNAME` | Undefine a conditional compilation symbol, except `PXX`. |
| `-FuDIR` | Add a Pascal unit search root. |
| `-IDIR` | Add a C include directory and a Pascal unit search root. |
| `-Mobjfpc` | Accept the Object Pascal compatibility mode marker. |
| `--threadsafe` | Use atomic refcounts for managed strings and arrays. On x86-64, i386, aarch64, and arm32 only. |
| `--no-auto-var` | Disable auto-typed variable declarations. |
| `--no-lazy-var` | Disable inline/lazy variable declarations. |
| `--system-libs` | Disable the Magic Link auto-pull mechanism and link C dependencies dynamically. |
| `--system-libs=stems` | Granular opt-out: dynamically link listed comma-separated C libraries (e.g. `m,pthread`), keeping the rest magic-linked. |
| `-nostdinc` / `--nostdinc` | Disable adding default C header search directories. |

## Strictness and dialect

PXX is lax by default and turns FPC-parity checks on individually. See the
[compiler modes](./modes.md) page for the whole lax → `--strict` → granular →
`--mimic-fpc` model; each flag below is documented there in context. The
directive column names the in-source [directive](./directives.md) with the same
effect where one exists.

| Option | Effect | Directive |
| --- | --- | --- |
| `--strict` | FPC-parity strictness umbrella (currently the routine-visibility check below). | `{$STRICT ON}` |
| `--require-forward` | A routine must be defined above its call, `forward;`-declared, in an interface section, or be a class method — no whole-source pre-scan. First check under `--strict`. | `{$STRICT ON}` |
| `--strict-overload` | Require explicit `overload;` on overloaded routines. | `{$STRICT_OVERLOAD ON}` |
| `--permissive-overload` | Relax the overload marker requirement (the default). | `{$STRICT_OVERLOAD OFF}` |
| `--strict-operator` | FPC-parity rejection of `=` / `<>` on class operands (lax default allows them). | `{$STRICT_OPERATOR ON}` |
| `--strict-case` | FPC-parity `case`-label diagnostics: inverted ranges, duplicate/overlapping labels. | `{$STRICT_CASE ON}` |
| `--strict-visibility` | Enforce `private` / `protected` / `strict` member access (lax default parses the markers but grants access anywhere). | `{$STRICT_VISIBILITY ON}` |
| `--lax-decl-order` | Opt *out* of declare-before-use gating for forward-visible globals (strict/FPC-parity is the default). | `{$DECLORDER OFF}` |
| `--auto-locals` | Assignment to an undeclared name declares a routine-local inferred-type var instead of erroring. Off by default (masks typos). | `{$IMPLICITVARS ON}` |
| `--mimic-fpc` | FPC-compatibility preset: the curated FPC define set plus `--require-forward`, `{$I+}`, and `--strict-visibility`. See [FPC compatibility](../language/fpc-compatibility.md). | `{$MIMIC FPC}` |

## Runtime and codegen

| Option | Effect |
| --- | --- |
| `-O0` … `-O3` | Optimization level. `-O2` is the proven default; `-O3` carries newer, still-promoting passes. `-g` implies `-O0` unless an `-O` level is given explicitly. |
| `--no-default-rtl` | Do not pull the default standard-unit surface (textfile + builtin). Used by the compiler self-build. |
| `--no-div-check` | Opt out of the integer div/mod pre-divide zero check (default on: divide by zero raises a clean runtime error rather than a raw `SIGFPE`). |
| `--no-signals` | Opt out of the default signal runtime (graceful `SIGINT`/`SIGTERM` dispatch + `SetSignalHandler`). PC targets only. |
| `--no-unhandled-handler` | Do not install the default unhandled-exception handler. |
| `--no-strict-ir` | Opt out of the self-host IR guard (the hard error on any unlowered IR node). For an in-development frontend only. |
| `--max-stack-frame=N` | Set the oversized-stack-frame warning threshold in bytes (`=0` disables it). |
| `--werror` / `-Werror` | Promote any warning to a fatal error. |
| `--xtensa-soft-divide` / `--xtensa-cpu=lx6` | Route div/mod through software helpers (ESP32 classic LX6, no hardware divide). |

`--experimental-ir-codegen` is accepted as a deprecated no-op (IR is the only
backend).

## Diagnostics and internal flags

These serve compiler development and self-inspection, not normal builds. Use
them only when directed.

| Option | Effect |
| --- | --- |
| `--dump-cpp` | Dump the intermediate C++-ish form. |
| `--proc-map` | Dump the procedure map. |
| `--selftest` | Run the built-in self-test. |
| `--measure-inline` / `--measure-regcall` | Emit inline / register-call instrumentation. |
| `--warn-missed-fold` | Warn on constant-fold opportunities the optimizer missed. |
| `--warn-self-result` | Warn when a parameterless function's bare own name is read as its `Result`. |

## Search paths

The wrapper created by `install.sh` already passes the bundled `lib/` roots.
Use `-Fu` for project-local units:

```sh
./pxx -Fusrc -Fulib/more app.pas app
```

Search roots are checked in flag order before the default library roots. That
lets a project override or add units deliberately without changing the checkout.

Use `-I` for C headers. It also feeds the Pascal unit search path, which is
useful for generated bindings that sit next to the imported header:

```sh
./pxx -Iinclude main.pas main
```

## Examples

```sh
./pxx hello.pas hello
./pxx -g hello.pas hello
./pxx --target=aarch64 hello.pas hello.a64
./pxx -dDEBUG hello.pas hello
./pxx -Fusrc -Iinclude app.pas app
./pxx --target=riscv32 --esp-profile=bare main.pas main.o
```

## Next

- [Compiler modes and strictness](./modes.md)
- [Compiler directives](./directives.md)
- [Install](../install/)
- [Targets](../targets/)
