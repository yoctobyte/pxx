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

The frontend is selected by the source file's extension: `.pas`/`.pp` for
Pascal, `.c` for [C](../targets/c-frontend.md), `.npy` or `.py` for
[Nil Python](../targets/nil-python.md), and `.asm` for the assembly-source
frontend.

With an output path, PXX writes the executable there and emits a matching map
file. Without an output path, it derives one from the source name and refuses to
overwrite the source.

An output path ending in `.o` also selects object-output mode, the same as
passing `--emit-obj`. An output path ending in `.so` selects shared-library
mode, the same as passing `--shared`.

## Information flags

These answer a question about the toolchain itself and need **no source file**.
Each exits 0.

| Flag | Answers |
| --- | --- |
| `--help`, `-h` | usage, plus the options worth remembering |
| `--version` | generation, the frontends built in, the host |
| `--where`, `--config` | every path the compiler resolves, and which tier it came from |
| `--list-targets` | the `--target=` values, and which of them run on this host |
| `--list-libraries` | the units this binary can actually find, grouped by directory |
| `--doctor` | what this box can do — cross-run, ESP, gdb, FPC seed, gcc |

`--version` names the compiler generation — the same number a
`{$IF PXX_VERSION >= n}` directive tests — and which binary this is:

```
pxx (pascal26) — self-hosting Pascal-dialect compiler
  generation:  26   (the value {$IF PXX_VERSION >= n} tests)
  frontends:   pascal c nilpy rust zig ada basic fortran algol erlang lolcode whitespace
  host arch:   x86-64 linux
  build:       sha256 d67ea56f34a7   (sha256sum of this binary, first 12)
  release:     v0.1.0-beta.1 "Blaise"   (MANIFEST.sha256 names this binary)
  source:      ab6ab895b9bc   (the commit the release was built from)
```

The `build:` line is always there. The compiler hashes its own binary each
time `--version` runs, which takes about half a second. The lines under it come
from a record next to the binary that lists that hash:

- In a release archive, `MANIFEST.sha256` and `RELEASE-ID` give `release:` and
  `source:`, and `pin:` when the release binary is a pin.
- In a clone, `stable_linux_amd64/default/pin.log` gives `pin:` and `source:`.
  A compiler built by `make` gives `local:` and the source hash from
  `compiler/.pascal26.fixedpoint`.
- A binary that no record names gives `local: not a pin or a release binary`.

The example above is from a test bundle, not a published release. `--doctor`
prints the same lines at the top of its report.

That frontend list is every frontend compiled into the binary, and they sit at
very different stages. The ones these docs cover in depth are Pascal,
[C](../targets/c-frontend.md) and [Nil Python](../targets/nil-python.md); the
rest are a real BASIC frontend, two experimental ones, and six skeleton probes,
and their presence in the list is not a support claim. See
[Other frontends](../targets/other-frontends.md) for which is which.

### `--where` — the one to reach for first

When a build cannot find a unit or a header, `--where` is the answer, because it
prints the paths **from the code that resolves them** rather than from a rule
written down separately. It marks each root that does not exist `[MISSING]`, and
ends with the tier order in force:

```
Library roots (as ParseUsesUnit resolves them):
  /opt/pxx/lib/rtl/   [RTL]
  /opt/pxx/lib/pcl/   [PCL]
  ...

Pascal unit search roots, in order (-Fu goes in FRONT of these):
  /opt/pxx/../lib/rtl/platform/posix/   [MISSING]
  /opt/pxx/lib/rtl/platform/posix/

Tier order: -Fu/-I  >  PXX_HOME/PXX_LIBPATH  >  pxx.cfg  >  exe-dir defaults.
```

`--config` is an exact alias — same output, same exit — for when the question is
phrased as "which `pxx.cfg` is in effect?" rather than "where is the RTL?".
(Deliberately not called "byte-identical": in these docs that phrase is reserved
for two specific technical claims, and reusing it for two flags that print the
same thing would blur a distinction worth keeping. The two claims are **not the
same claim** — in the self-host fixedpoint it is the *binary* that is identical,
to our own previous output; in the gcc-oracle corpora it is a compiled program's
*output* that is identical, to the output of the same program built with gcc.
PXX does not emit gcc's machine code. See
[Status](status.md#what-works-means-here).)

One subtlety worth knowing: `-Fu` and `-I` given **before** `--where` on the
command line appear in its output, and ones given after it do not — `--where`
answers where it is read.

### `--doctor` — capability, not correctness

`--doctor` reports what this box can do with this binary: native compilation,
whether the RTL, builtin units and C headers were found, which cross targets can
actually be *run* here through qemu, whether an ESP-IDF and Espressif toolchain
are present, and whether an FPC seed, gdb and gcc are around for compiler
development. Every `no` row names what to install.

**Nothing in it is fatal.** Compiling and running a native program needs none of
the optional rows; each `no` costs exactly the one capability its row names.

## Options

| Option | Effect |
| --- | --- |
| `--target=ARCH` | Select `x86_64`, `i386`, `aarch64`, `arm32`, `riscv32`, `xtensa` or `wasm32`, or an ESP chip name (`esp32`, `esp32s2`, `esp32s3`, `esp32c2`, `esp32c3`, `esp32c6`, `esp32h2`, `esp32p4`), which implies its CPU and `--platform=esp`. `--list-targets` prints the list. |
| `--platform=posix\|esp\|wasi` | Select the platform layer explicitly. A target or chip name normally implies it. |
| `--xtensa-abi=call0\|windowed` | Select the Xtensa call ABI. |
| `--xtensa-cpu=lx6` | Use the older ESP32 LX6 software divide/mod profile. |
| `--xtensa-fpu` | Use Xtensa hardware single-precision float operations where supported. |
| `--esp-profile=bare` | Select the bare-metal ESP platform profile for `riscv32` or `xtensa`. |
| `--emit-obj` | Emit a relocatable object (`.o`) instead of a linked executable. `x86-64`, `i386`, `aarch64`, `arm32`, `riscv32` and `xtensa` write a general object — code, data, bss, relocations, exported symbols — for a compiled source; `.asm` sources produce objects on x86-64 only. The export surface is the C-convention routines, so in practice the source must be Pascal or C — no other frontend has a spelling that marks a routine `cdecl`, and an object that would define no linkable symbol is refused rather than written. The `aarch64` and `arm32` writers are newer (2026-09-22) and their linking is not yet documented. On x86-64 and i386 the export surface is the C-convention routines; an x86-64 object is position-independent and links with no extra flags, an i386 one needs `-no-pie` — see [Linking a pxx object into another program](./objects.md). Same as an output path ending in `.o`. |
| `--shared` | Emit an ET_DYN shared library (`.so`) instead of an executable. x86-64 only. Works for compiled sources (Pascal or C — the same C-convention export surface as `--emit-obj`, and no other frontend can spell it) as well as the `.asm` frontend; the export surface is the C-convention routines, as for `--emit-obj`, and the library both links with `ld` and loads with `dlopen` — see [Linking a pxx object into another program](./objects.md). Same as an output path ending in `.so`. |
| `-S` | Also write `<output>.s`, a best-effort x86-64 disassembly text dump of the emitted code. Additive — the normal output (executable, `--emit-obj`, or `--shared`) still happens. x86-64 only. |
| `-g` | Emit DWARF debug information. |
| `--debug` | Print compiler tracing diagnostics. |
| `--dump-ir` | Print lowered IR while still emitting output. |
| `--dump-rtti` | Print generated RTTI tables while still emitting output. |
| `-dNAME` | Define a conditional compilation symbol. |
| `-uNAME` | Undefine a conditional compilation symbol, except `PXX`. |
| `-FiDIR` | Add a search root for `{$I}` include files. |
| `-FuDIR` | Add a search root: a Pascal unit directory, and the directory a Nil Python `import` searches for a third-party package (point it at the package's **parent**). See [Nil Python](../targets/nil-python.md#finding-a-third-party-python-package-fu). |
| `-IDIR` | Add a C include directory and a Pascal unit search root. |
| `-include FILE` | C: preprocess `FILE` as if `#include "FILE"` were the first line of the source, without shifting its line numbers. |
| `-fsigned-char` / `-funsigned-char` | C: make plain `char` signed or unsigned, overriding the target's default. |
| `-M<mode>` | FPC's mode switch, for sources that carry no `{$MODE}` line. `-Mdelphi` (and `-Mdelphiunicode`) selects Delphi mode; every other name (`-Mobjfpc`, `-Mtp`, …) is accepted and leaves the default dialect. A `{$MODE}` in the source still wins. |
| `--threadsafe` | Use atomic refcounts for managed strings and arrays. On x86-64, i386, aarch64, and arm32 only. |
| `--no-auto-var` | Disable the `auto` type keyword (`var n: auto := 'x';`) and inline loop variables (`for var i := …`, `for var x in …`). `var x := 5;` inside a block still infers its type; `--no-lazy-var` is what turns that off. |
| `--no-lazy-var` | Disable inline/lazy variable declarations (`var x := 5;` inside a block). The error says so: "inline `var` declarations are disabled by --no-lazy-var; drop that option to allow them". |
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
| `--strict-fpc` | The FPC-parity umbrella: `--strict-case`, `--strict-operator`, `--strict-visibility` and `--require-forward` together — the checks that match FPC *and* are proven against the real FPC corpora. Also switches two rules that change a *value* rather than a diagnostic: FPC shift widths, and `Variant`→`Char`. `--strict-overload` is deliberately **not** included; see [modes](./modes.md). | `{$STRICT_FPC ON}` |
| `--require-forward` | A routine must be defined above its call, `forward;`-declared, in an interface section, or be a class method — no whole-source pre-scan. First check under `--strict`. | `{$STRICT ON}` |
| `--strict-overload` | Require explicit `overload;` on overloaded routines. | `{$STRICT_OVERLOAD ON}` |
| `--permissive-overload` | Relax the overload marker requirement (the default). | `{$STRICT_OVERLOAD OFF}` |
| `--strict-overload-width` | Among integer overloads, pick the **narrowest that fits**, as FPC does, instead of the default dialect's widening. Changes which body a call binds to, so it is deliberately **not** in `--strict-fpc`; see [modes](./modes.md), which carries the value table. | — command line only |
| `--strict-operator` | FPC-parity rejection of an `operator =` or `operator <>` *overload* for a class type (FPC predefines both as reference equality). The lax default allows the overload and uses it for value equality. Comparing two class variables with `=` is allowed either way. | `{$STRICT_OPERATOR ON}` |
| `--strict-case` | FPC-parity `case`-label diagnostics: inverted ranges, duplicate/overlapping labels. | `{$STRICT_CASE ON}` |
| `--strict-visibility` | Enforce `private` / `protected` / `strict` member access (lax default parses the markers but grants access anywhere). | `{$STRICT_VISIBILITY ON}` |
| `--lax-decl-order` | Opt *out* of declare-before-use gating for forward-visible globals (strict/FPC-parity is the default). | `{$DECLORDER OFF}` |
| `--auto-locals` | Assignment to an undeclared name declares a routine-local inferred-type var instead of erroring. Off by default (masks typos). | `{$IMPLICITVARS ON}` |
| `--mimic-fpc` | FPC-compatibility preset: the curated FPC define set plus `--require-forward`, `{$I+}`, and `--strict-visibility`. See [FPC compatibility](../language/fpc-compatibility.md). | `{$MIMIC FPC}` |
| `--mimic-fpc-compiler` | `--mimic-fpc` plus the build-time defines FPC's makefile passes when compiling FPC's own compiler sources. | — |
| `--strict-python` | The CPython-parity umbrella for Nil Python. It is accepted and has no rules yet, so today it refuses nothing. | — |
| `--strict-uses` / `--no-strict-uses` | Accepted and ignored. A unit's `uses` never leaks to its importers; there is no switch for it. | — |

## Runtime and codegen

| Option | Effect |
| --- | --- |
| `-O0` … `-O3` | Optimization level. `-O2` is the proven default; `-O3` carries newer, still-promoting passes. `-g` implies `-O0` unless an `-O` level is given explicitly. |
| `-OO` | Emit what the source says, 1:1, with no folding at all. A diagnostic reference, not a shipping mode: it keeps calls the program cannot reach. |
| `--no-assertions` | Compile every `Assert` out, condition included, as if each file began with `{$ASSERTIONS OFF}`. A later `{$ASSERTIONS ON}` in a source still wins. |
| `-Sa` | FPC's "assertions on". That is already the PXX default, so it changes nothing. |
| `--fpc-mem-errors` | Emulate FPC's memory-fault behaviour: a nil read or write, a call through a nil procvar or a wild store prints `Runtime error 216 (...)` and exits 216, instead of dying on `SIGSEGV` (exit 139) with no message. |
| `--rtl-libc` | Reach the kernel through libc's `syscall(3)` instead of the raw instruction, for hosts that forbid raw syscalls. x86-64 only; the program then needs `libc.so.6`. |
| `--compact-classes` / `--no-compact-classes` | Reserve no VMT slots for `TObject`'s root virtuals, which saves about 24-32 bytes per class declared. Overriding `Equals`, `GetHashCode` or `ToString` is then a compile error naming the flag. Implied by `--platform=esp`; pass `--no-compact-classes` after it to opt back in. |
| `--no-ro-data` | Keep all data in the one read-write segment, instead of putting literals in a read-only one. |
| `--ro-rtti` / `--no-ro-rtti` | Class RTTI and VMTs go in the read-only segment by default; `--no-ro-rtti` puts them back in the writable one. |
| `--function-sections` | With `--emit-obj` (x86-64): one `.text.<name>` section per routine, so a linker can drop what nothing reaches. |
| `--link [-o OUT] OBJ... [OUT]` | Link x86-64 objects that `pxx --emit-obj` wrote into a static executable, with no external linker and no libc. It supplies `_start` unless an object defines one, and drops sections the entry cannot reach (`--no-gc-sections` keeps them). Objects from gcc or FPC, archives and shared objects are refused by design. |
| `--dce` / `--no-dce`, `--dce-report`, `--dce-why[=NAME]`, `--dce-cost=`, `--dce-reach-from=` | Drop routine bodies nothing can reach, and report on that pass: `--dce-report` prints what it kept and dropped, and the others explain why a body is live. |
| `--gtk=2\|3\|4` | Which GTK's headers the C resolver searches and which library it links. It does not port the GTK 3 widget layer in `lib/pcl`. |
| `--no-default-rtl` | Do not pull the default standard-unit surface (textfile + builtin). Used by the compiler self-build. |
| `--no-div-check` | Opt out of the integer div/mod pre-divide zero check (default on: divide by zero raises a clean runtime error rather than a raw `SIGFPE`). |
| `--no-nil-check` | Opt out of **all** emitted nil checks, including those a source turned on with `{$NILCHECKS ON}`. Call sites are checked by default (a method on a nil instance, or a call through a nil procvar, method pointer or interface); bare `p^` derefs are not. A checked site raises a catchable `EAccessViolation` with `SysUtils`, else `Runtime error 216`. See [directives](./directives.md#nilchecks-is-tri-state). |
| `--no-signals` | Opt out of the default signal runtime (graceful `SIGINT`/`SIGTERM` dispatch + `SetSignalHandler`). PC targets only. |
| `--fpc-float-errors` | Emulate FPC's float error behaviour: unmask invalid / zero-divide / overflow at entry (the set FPC itself unmasks) and report a trap as FPC's runtime error — 208 float division by zero, 205 overflow, 207 invalid. Off by default; see below. x86-64 only, and it needs the signal runtime (so not with `--no-signals`). |
| `--no-unhandled-handler` | Do not install the default unhandled-exception handler. |
| `--no-strict-ir` | Opt out of the self-host IR guard (the hard error on any unlowered IR node). For an in-development frontend only. |
| `--strict-ir` | Accepted no-op: the IR guard is the default now. Kept so existing invocations keep working. |
| `--map` / `--no-map` | Force the map file next to the output on or off. A map is written by default when an output path is given. |
| `--no-shims` | Resolve a Nil Python import as if PXX shipped nothing of its own for that name: no `mimic_<module>` substitution, and no curated `lib/rtl` unit serving a Python module (`math`, `json`, `re`, `zlib`, …). A host C header is then reachable by its bare name. Turns "compiled without compatibility shims" from a claim into a checked property. Nil Python only; see [shims](../targets/nil-python.md#shims-standing-in-for-a-python-package). |
| `--max-stack-frame=N` | Set the oversized-stack-frame warning threshold in bytes (`=0` disables it). |
| `--werror` / `-Werror` | Promote any warning to a fatal error. |
| `--xtensa-soft-divide` / `--xtensa-cpu=lx6` | Route div/mod through software helpers (ESP32 classic LX6, no hardware divide). |
| `--xtensa-long-calls` | Reserve the long call form at every forward call, so a callee more than 512 KiB ahead is reachable. Off by default; the Nil Python example builds for the Xtensa chips pass it. |
| `--xtensa-soft-mulhigh` | Replace the 32-bit multiply-high instruction with a software routine, for QEMU's Xtensa cores, which lack it. |

`--experimental-ir-codegen` is accepted as a deprecated no-op (IR is the only
backend). `-fno-auto-var`, `-fno-lazy-var` and `-fno-unhandled-handler` are
aliases of the `--no-…` flags above.

### Float errors are quiet by default

The default is the part a Pascal reader will not expect, and it is a decision
rather than an omission: PXX leaves the float exceptions masked, so `1.0/0.0`
evaluates to `+Inf`, `0.0/0.0` to `NaN`, and the program keeps running. FPC
unmasks at startup and aborts; PXX does not. The reasoning is that measurement
and streaming data with out-of-bounds inputs is better served by `Inf`/`NaN`
propagating through a computation than by an abort partway into it.

`--fpc-float-errors` is how a program asks for FPC's behaviour instead. The same
program compiled with and without it:

```console
$ pxx --fpc-float-errors trap.pas trap && ./trap div
Runtime error 208 (division by zero)          # exit status 208

$ pxx trap.pas trap && ./trap div
no trap, r=  Inf                              # exit status 0
```

Overflow (`1e308 * 10`) reports 205 and invalid (`0.0/0.0`) reports 207 under
the flag. Underflow and inexact stay masked, exactly as they do under FPC, so
runtime error 206 is decoded but never armed by the flag alone.

The flag is program-wide and set at compile time. To change the mask for one
region at runtime, use `GetExceptionMask` / `SetExceptionMask` from the `math`
unit, which take and return an FPC-compatible `TFPUExceptionMask`.

## Diagnostics and internal flags

The `--warn-*` flags are diagnostics you can run against ordinary source; none
changes what is compiled. All but `--warn-self-result` are off by default. The dump and
measure flags below them serve compiler development and self-inspection — use
those only when directed.

| Option | Effect |
| --- | --- |
| `--dump-cpp` | C sources: print the preprocessed source (after `#include` and `#define`) and stop, writing no output. |
| `--proc-map` | Dump the procedure map. |
| `--measure-inline` / `--measure-regcall` | Emit inline / register-call instrumentation. |
| `--warn-missed-fold` | Warn on constant-fold opportunities the optimizer missed. |
| `--warn-self-result` / `--no-warn-self-result` | Warn when a parameterless function's bare own name is read as its `Result`. **On by default**, because that line means a recursive call in Delphi mode; `--no-warn-self-result` silences it. |
| `--warn-uses-leak` | Warn whenever a name resolves through a unit not reachable by the non-transitive `uses` rule. Read-only measurement — resolution itself is unchanged. |
| `--warn-ignored-directives` | Report a routine directive that is accepted but cannot be honored *here*, naming the reason (`cdecl`, `register`, `iram` off the ESP targets, `stackful`, `reintroduce`, and `inline` when the routine cannot be inlined). Diagnostic only — codegen is unchanged. See [routine directives](../language/dialect.md). |

## Search paths

The wrapper created by `install.sh` already passes the bundled `lib/` roots.
Use `-Fu` for project-local units:

```sh
./pxx -Fusrc -Fulib/more app.pas app
```

Search roots are checked in flag order before the default library roots. That
lets a project override or add units deliberately without changing the checkout.

The full order — flags, then environment, then `pxx.cfg`, then the defaults
guessed from the binary's location — is printed by `pxx --where` (see
[Information flags](#information-flags) above), which reads it from the resolver
itself. Prefer running it over trusting a copy of the rule.

Use `-I` for C headers. It also feeds the Pascal unit search path, which is
useful for generated bindings that sit next to the imported header:

```sh
./pxx -Iinclude main.pas main
```

## Environment and `pxx.cfg`

Three environment variables and one optional config file sit between the
command-line flags and the defaults the compiler guesses from its own location.
Run `pxx --where` to see which of them are actually in effect — it prints all
of them, set or unset.

| Variable | Effect |
| --- | --- |
| `PXX_HOME=<root>` | Install root. Its `lib/` and `compiler/builtin/` **replace** the roots guessed from the binary's own directory. |
| `PXX_LIBPATH=a:b` | Extra Pascal unit roots, inserted after `-Fu` and before the defaults. |
| `PXX_CONFIG=<file>` | Use this config file instead of searching for one. |
| `PXXDBG=<topics>` | Compiler-internal probes, for compiler development; `PXXDBG=help` lists the form. |

`PXX_HOME` is what makes an unpacked tarball work from any directory, and it is
honoured **all-or-nothing**: the exe-dir guesses are not kept underneath it as a
fallback. Point it at the wrong root and the RTL is simply not found —

```
error: uses: unit source not found: builtinheap
```

— which is `--where` territory, and every root will be marked `[MISSING]`.

### The config file

If `PXX_CONFIG` is unset, the compiler takes the first of these that exists:
`./pxx.cfg`, `~/.config/pxx/pxx.cfg`, `<exe dir>/pxx.cfg`. Three directives are
understood today:

```
home      /opt/pxx
unitpath  /opt/units
incpath   /opt/inc
```

`--where` echoes the file it chose and the directives it read from it, so a
config that is not taking effect is one command away from explaining itself.
Per-library define and mode manifests are not implemented.

## Examples

```sh
./pxx --where
./pxx --doctor
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
- [Install](../install/index.md)
- [Targets](../targets/index.md)
