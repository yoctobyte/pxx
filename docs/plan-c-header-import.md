# Plan: Real C Header Import (glib/GTK-grade)

Status: in progress. Owner doc for todo §2c. Companion to `C_INTEROP.md`
(current behaviour) and `docs/gui.md` (why the hand-written GTK binding exists).

## Progress (2026-06-01)

- **Pillar 1, partial.** DT_NEEDED is deduplicated — one entry per distinct
  library, not per imported symbol (`elfwriter.inc` `PrepareDynamicData` /
  `PatchDynamicData`, `DynamicNeededCount`). The unversioned `lib<name>.so`
  guess is replaced by a soname table for the FFI targets in use (libc.so.6,
  libm.so.6, libpthread.so.0, libdl.so.2, librt.so.1, libz.so.1) in
  `parser.inc`. **Deferred:** the dynamic `ld.so.cache`/`DT_SONAME` probe and
  link directives (1a/1b/1c). Note: the self-hosted compiler has no `execve`
  (runtime syscalls are read/write/open/close/mmap/brk/exit only), so
  pkg-config/ldconfig shelling is not available — the probe must parse
  `/etc/ld.so.cache` or read `DT_SONAME` from candidate `.so` files via plain
  file I/O.
- **Stage A, done.** Real C type model: distinct lexer tokens for
  void/short/long/signed/unsigned/float/double/_Bool; `ParseCDeclType` folds a
  declaration-specifier sequence + pointer suffix into one canonical
  Pascal/ABI `TTypeKind` (long->tyInt64, short->tyInt16, unsigned widths, any
  pointer->tyPointer, bare void->`CTypeIsVoid`). Widths flow through the
  size-aware prologue/`ParamSize`. Bare `return;` allowed in C bodies.
  Regression: `test/test_c_widths.pas`. 16-param cap retained; SSE float
  arg/return ABI still absent (libm blocked on it).
- **Stage B, done (core).** typedef + enum + opaque struct/union.
  Case-sensitive `CTypedef` table; `ParseCTypedef` registers scalar/pointer
  aliases, opaque struct/union (`typedef struct _X X;` -> Pointer), enum
  typedefs, and function-pointer typedefs (-> Pointer). `ParseCDeclType`
  resolves typedef names in type position. Enumerators become Int32 constants
  (`AddConst`) via a small integer constant-expression evaluator that handles
  `(1<<N)`, `A|B`, etc. (the C lexer splits `<<` into two `tkLt`, `|` into
  `tkOr`). Regressions: `test/test_c_typedef.pas`, `test/test_c_enum.pas`.
  Full struct field layout is deferred per the original plan — opaque
  pointer-only suffices for the pthread/GTK call surface, which touches these
  structs only through pointers.
- **Float C-call ABI, done.** External calls follow the SysV AMD64 FP
  convention: float args fill xmm0..xmm7, integer/pointer args fill the six
  integer registers, classes counted independently; float/double return read
  from xmm0 into rax; AL set to the vector count for variadics. Applies to
  `ProcExternal` calls only — internal Pascal calls keep the all-integer
  convention. libm works via `external 'libm.so.6'`. Regression:
  `test/test_c_float.pas` (pow/sqrt/ldexp). Still absent: >6 integer / >8
  vector argument stack spill.
- **Next:** a real pthread end-to-end (header import + `pthread_create`/
  `pthread_join`); then Stage C macro soup + >6-arg stack spill (gtk).

## Goal

`uses gtk;` (or `uses gtk3;`) resolves the installed `/usr/include/gtk-3.0/...`
headers, digests enough of glib/GTK's macro and type soup to expose the called
functions as externals, and links against the **soname the system actually
ships** — discovered at compile time, not pinned in source. A plain recompile
on a different box with a different GTK micro/minor version just works. No
hand-redeclared prototypes, no baked `libgtk-3.so.0` string.

Success criterion: a stock Lazarus/GTK helloworld that today needs
`test/gui/gtk3.pas` (hand binding) instead compiles from `uses gtk;`, and the
emitted ELF's `DT_NEEDED` matches `ldconfig -p` on the build host.

Non-goals: full C ABI, C++ name mangling, compiling GTK *source*, a conformant
C frontend. We parse declarations well enough to call functions and lay out the
structs/enums we touch; everything else we tolerate and skip.

## Why this is two problems, not one

1. **Soname resolution** — knowing which `.so` to record in `DT_NEEDED`,
   derived from the system rather than guessed. Mostly mechanical; unblocks the
   "recompile matches the system" half of the goal independently of header
   depth. Do this first — it is also useful for the existing `external 'soname'`
   path.

2. **Header frontend depth** — surviving glib/GTK headers: nested includes,
   function-like macros, `typedef`/`struct`/`enum`/pointer churn, GCC attribute
   spellings, platform conditionals, function-pointer typedefs. This is the hard
   part and the bulk of the work.

They are independent. Pillar 1 lands value on day one (the hand bindings stop
hardcoding sonames); Pillar 2 is the long arc.

---

## Current state (baseline — measured 2026-05-31)

`compiler/clexer.inc` (334 ln), `compiler/cparser.inc` (358 ln),
`compiler/cpreproc.inc` (825 ln).

- **Lexer type words** (`CKeyword`): `char`→`tkChar_T`; `int`,`void`,`long`,
  `short`,`signed`,`unsigned`,`double`→`tkInteger_T`. So **all width and
  signedness is lost**, `void` is indistinguishable from `int`, no float type.
- **Parser** (`ParseCSubroutine`/`ParseCUnit`): a declaration is recognised
  only if it *starts* with `int`/`char` (`IsCTypeTok`). Params: `int`/`char`
  only, `*` consumed and discarded (pointers are not a distinct type), max 16.
  A prototype ending in `;` becomes `ProcExternal` with `ProcLibrary :=
  CurrentCLibrary`. `typedef`/`struct`/`enum`/`#`-anything at top level is
  skipped token-by-token.
- **Soname** (`parser.inc` ~4960): `ctype` and `math_ext` → `libc.so.6`;
  every other header unit → `lib<name>.so` (literal, unversioned guess).
- **Preprocessor**: `#include`, include guards, `#define`/`#undef`, object +
  basic function-like macros, `#if/#ifdef/#ifndef/#elif/#else/#endif`. Missing:
  token paste `##`, stringify `#`, variadic macros, full rescanning, `defined()`
  in complex expressions, builtin/predefined macros.
- Unit search order: source dir → `compiler/` → `lib/rtl` → `lib/lcl` →
  `/usr/include/`. A `.h` hit sets `isCHeader` and routes through the C path.

Implication: today's importer can ingest `ctype.h`-class headers (flat int/char
prototypes) and nothing structurally harder. GTK is far out of reach.

---

## Pillar 1 — Soname resolution

Replace the `lib<name>.so` guess with a real lookup, and let any binding (header
*or* hand-written `external`) name a *logical* library that resolves to a
concrete soname at compile time.

### 1a. Soname probe

Given a logical library name, produce the soname to record in `DT_NEEDED`.
Resolution order, first hit wins:

1. **Explicit pin** in source (escape hatch, see 1b).
2. **pkg-config**: `pkg-config --libs <pkg>` → `-lgtk-3` → map `-lNAME` to a
   file via the linker search, then read that file's `DT_SONAME`. The pkg name
   (`gtk+-3.0`) differs from the unit name (`gtk`), so a small alias table or a
   `{$LINKPKG gtk+-3.0}` directive bridges it.
3. **ldconfig cache**: `ldconfig -p | grep libNAME` → path → `DT_SONAME`.
4. **Direct file**: probe `libNAME.so`, `libNAME.so.*` in the standard search
   dirs; read `DT_SONAME`.
5. Fall back to today's `lib<name>.so` guess (keeps current behaviour working).

The authoritative value is the `.so` file's own **`DT_SONAME`** dynamic entry
(e.g. `libgtk-3.so.0`), not the filename or symlink target — that is exactly
what a normal linker records and what guarantees "recompile matches the system".
The ELF reader for this is small; the compiler already *writes* `DT_*` entries
(`elfwriter.inc`), so reading them is symmetric work.

Probing shells out to `pkg-config`/`ldconfig` at compile time. That is a
compile-host dependency, not a runtime one — acceptable, and gated so a missing
tool just falls through to the next method.

### 1b. Source-level link directives

So the soname follows the system without being hand-pinned, but stays
overridable:

- `{$LINKLIB gtk-3}` — resolve logical name `gtk-3` via the 1a probe.
- `{$LINKPKG gtk+-3.0}` — resolve via a specific pkg-config package.
- Keep `external 'libfoo.so.0'` working verbatim (explicit pin = method 1).

A header unit carries its link directive at the top of its `.pas` binding (for
hand bindings) or is associated by the header→pkg alias table (for real header
import). The existing `ctype`/`math_ext`→`libc.so.6` special case becomes one
row in that alias table instead of an `if`.

### 1c. Multiple needed libraries per unit

GTK pulls `libgtk-3`, `libgobject-2.0`, `libglib-2.0`, `libgdk-3`, … A unit must
be able to record several `DT_NEEDED` entries, and each imported symbol must be
attributed to the right one. `ProcLibrary` is already per-proc (`defs.inc`
`ProcLibrary[]`), so the data model supports it; the resolution layer must pick
the correct soname per symbol (pkg-config `--libs` gives the full set).

**Deliverable for Pillar 1**: hand bindings (and the eventual header import)
stop hardcoding sonames; `make test` still green; a regression that compiles a
tiny `external` against, say, `libm`/`libz` and asserts the emitted `DT_NEEDED`
equals the host's `DT_SONAME`.

---

## Pillar 2 — Header frontend depth

Staged so each stage is independently testable against progressively harder
real headers. Pick concrete header targets per stage as the gate.

### Stage A — C type model (foundation for everything after)

Today there is no C type beyond int/char. Add a real-enough model:

- **Lexer**: stop collapsing type words. Emit distinct tokens (or a single
  `tkCType` carrying the spelling) for `void`,`char`,`short`,`int`,`long`,
  `float`,`double`,`signed`,`unsigned`,`_Bool`, plus the stdint names that
  arrive as typedefs (`int8_t`…`uint64_t`,`size_t`,`intptr_t`).
- **Type parser**: fold a declaration-specifier sequence
  (`unsigned long int`, `const char *`, …) into one canonical C type: base kind
  + width + signedness + pointer depth + const-ness. Map each to a Pascal/ABI
  type for codegen: integer widths → `tyInteger`/sized loads, any pointer →
  `Pointer`, `char*` → C string handling, `void` return → procedure, `float`/
  `double` → real (or explicitly *unsupported* with a clean skip if the SSE
  return/arg path isn't ready).
- This makes prototypes faithful: a `gpointer`/`GtkWidget*` param becomes a
  real `Pointer`, `gboolean` a 4-byte int, etc. The 16-param cap should grow or
  go (SysV: 6 integer regs then stack — the parser already special-cases 0..5;
  spill to stack for >6, or document the cap).

Gate: re-import `ctype.h` and a hand-picked simple system header (e.g.
`unistd.h` subset) with correct widths; widths verified by a test calling a
function whose result depends on getting the type right.

### Stage B — typedef / enum / struct

- **typedef**: register `typedef <type> <name>;` as a C type alias in a C-side
  alias table (separate from Pascal `AliasTk`, or reuse if clean). Resolve
  aliases when parsing later declarations. Handles the `typedef struct _X X;`
  forward-decl idiom (opaque pointer types — the GTK norm).
- **enum**: parse `enum { A, B=5, C }` → integer constants in the symbol table;
  anonymous enums are just named int constants. Enums are how GTK ships flags
  and modes; getting the constant *values* right matters for callers.
- **struct**: parse member lists into a layout (offset/size per field, C
  alignment rules). Most GTK structs are only ever touched as **opaque
  pointers**, so a first cut can record `struct X` as an opaque incomplete type
  (size unknown, pointer-only) and only compute full layout for structs whose
  fields we actually read. Function-pointer struct members (vtables) → typed as
  `Pointer` initially.
- **function-pointer typedef**: `typedef void (*GCallback)(void);` → a callable
  `Pointer` type. Needed for signal connect callbacks.

Gate: import a glib header that is mostly typedefs/enums (e.g. `glib/gtypes.h`
or `gobject/gtype.h` subset) without the parser derailing, and read at least one
enum constant value correctly from a test.

### Stage C — preprocessor hardening for macro soup

glib/GTK headers are macro-dense. Add, roughly in order of how often they block:

- **Builtin/predefined macros** the headers test for: `__GNUC__`, `__STDC__`,
  arch macros (`__x86_64__`), feature macros. Define a fixed, host-matching set
  so the right conditional branches are taken.
- **`defined()`** inside `#if` expressions, full integer `#if` constant-expr
  evaluation (operators, `&&`/`||`, nested).
- **Token paste `##`** and **stringify `#`** — used pervasively by the GObject
  type macros (`G_DECLARE_*`, `G_TYPE_CHECK_INSTANCE_CAST`, …).
- **Variadic macros** `__VA_ARGS__`.
- **Proper rescanning** of macro expansion output (current expander is partial).
- **GCC attribute spellings**: recognise and discard `__attribute__((...))`,
  `__extension__`, `__inline`, `__restrict`, `G_GNUC_*`, `_GLIBCXX_*` so they
  don't poison declaration parsing. A lexer-level skip of `__attribute__((…))`
  balanced parens is the cheap high-value win.

Many GObject macros that *generate code* (accessor boilerplate) we do **not**
need to expand for *calling* a library — we only need the function prototypes
and the type/enum constants. A pragmatic tactic: expand what's needed to keep
the declaration stream parseable, and skip macro *invocations* that expand to
declarations we don't consume. Decide explicitly per macro family whether to
expand or skip.

Gate: preprocess a top-level GTK header (`gtk/gtk.h` pulls hundreds of nested
includes) to completion without the preprocessor erroring — even if the parser
then skips much of it. Measure: how many prototypes survive as usable externals.

### Stage D — declaration recovery & robustness

Real headers will always contain constructs we don't model. The importer must
**degrade gracefully**: on an unparseable declaration, resync to the next
top-level `;`/`}` and continue, recording a skipped-count (surfaced under
`--debug`). Today's parser already skips unknown tokens; formalise it as
deliberate error recovery with a recovery point, so one weird declaration never
loses the rest of the header. A `--debug` summary ("imported N prototypes,
skipped M declarations") makes progress measurable header-to-header.

### Stage E — wire to the call/codegen path

- Imported prototypes flow into the same `ProcExternal` + `ProcLibrary` +
  PLT/GOT path used today and by hand bindings — no new backend.
- Pointer/`char*`/struct-pointer args marshalled per Stage A's type mapping.
- Name resolution: Pascal calls `gtk_init` → external symbol `gtk_init` in the
  soname from Pillar 1. Only **called** symbols get emitted into the dynsym /
  reloc tables (already true today), so importing a huge header stays cheap.

Gate: the success criterion — stock helloworld compiles from `uses gtk;`, runs,
`DT_NEEDED` matches the host.

---

## Suggested sequencing

1. **Pillar 1 (1a–1c)** — soname probe + link directives + multi-lib. Standalone
   value; de-risks the linking half; small ELF-reader addition.
2. **Stage A** — C type model. Unblocks every later stage; improves even the
   simple-header path.
3. **Stage B** — typedef/enum/opaque-struct.
4. **Stage C** — preprocessor hardening (the long pole; attack by real header).
5. **Stage D** — recovery/robustness (interleave with C as headers expose gaps).
6. **Stage E** — final wiring + the GTK gate.

Each stage gated by a concrete header target and a `make test` regression.
Protect the bootstrappable Pascal core throughout (per project policy): C
importer changes must not regress self-host fixedpoint.

## Risks / open questions

- **GObject macro generation**: deciding expand-vs-skip per macro family is the
  judgement-heavy part; mis-skipping loses prototypes, over-expanding may emit
  garbage declarations. Stage D recovery is the safety net.
- **Float/double ABI**: SSE arg/return path may not exist yet; Stage A should
  confirm before promising `gdouble` support, else mark unsupported.
- **Self-host stack limits**: the importer runs inside the self-hosted compiler;
  watch the same fixed-storage / no-open-array constraints noted in the state
  memory (large `UnitContent` buffers must stay global, etc.).
- **pkg-config absence**: probe must degrade to ldconfig/file/guess; never hard
  fail on a missing build tool.
- **Header version drift across hosts**: the whole point — verified by reading
  `DT_SONAME` from the resolved file rather than trusting a filename.

## Escape hatch stays

Hand-written `external 'soname'` bindings remain fully supported for symbols not
cleanly expressible from headers. Header import is the default path, not the
only one.
