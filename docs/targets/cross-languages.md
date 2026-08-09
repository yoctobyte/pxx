---
title: Cross languages
order: 62
---

# Cross languages

PXX is centered on Pascal, but several frontends share one backend, one symbol
table, and one `uses`/`import` resolver — the project's working nickname for
this is **Frankonpiler**. Pascal and C are mainline, gated frontends; Nil
Python is also mainline (see [Nil Python](./nil-python.md)); BASIC and Rust
remain experimental research paths.

## Frontends by suffix

| Suffix | Frontend |
| --- | --- |
| `.pas`, `.pp` | Pascal |
| `.c` | C |
| `.asm` | Assembly source (assemble + link to executable, `.o`, or `.so`) |
| `.bas` | BASIC, experimental |
| `.npy`, `.py` | Nil Python |
| `.rs` | Rust, experimental |

The Pascal frontend is the original, most complete surface. C and Nil Python
are full peer frontends with their own gates; BASIC and Rust exist to test
interop and backend reuse, and their accepted language subsets are still
moving.

BASIC (`.bas`) was PXX's first proof of this idea — a lexer/parser with a
totally different grammar than Pascal, calling into arbitrary Pascal and C
libraries through the same `USES` mechanism the other frontends use. It mixes
classic line-numbered control flow (`GOTO`/`GOSUB`) with modern numberless
loops (`FOR`/`WHILE`) in the same program by design — a deliberately
non-standard dialect, not a spec to conform to.

## Assembly source

The `.asm` frontend assembles a target's own assembly text and links it with the
compiler's built-in ELF writer — no external `as`/`ld`. It is the path that
validates the `--shared` (`.so`) and `--emit-obj` (`.o`) output modes. See the
[command-line reference](../reference/cli.md).

## Rust

The `.rs` frontend is an experimental research path that lowers a growing subset
of Rust (generics with trait bounds, enum-payload `match`) to the same IR. Like
BASIC, it exists to stress backend reuse across a very different grammar, not as
a usable Rust toolchain. Nil Python started in that same category and is no
longer in it — it is a gated mainline frontend, listed here only because it
shares the resolver.

## C Frontend

PXX features a C frontend that compiles `.c` source files directly to native executables. It supports a substantial subset of C, featuring a libc-free runtime and the "magic link" model.

See the dedicated [C Frontend](./c-frontend.md) page for details on compiling C, the linking model, and library configuration.

## C interop

PXX can import selected C headers and call shared-library symbols on supported
paths. This is useful for concrete bindings, but it is not a full C compiler or
full C ABI compatibility layer.

An `external` routine is called with the platform's C ABI automatically — a
`cdecl` marker on it is documentation, not instruction. The one place the marker
carries meaning is a **procedural type** used as a C function pointer, where
omitting it compiles a call that runs and returns the wrong value. See
[calling conventions](../language/dialect.md#calling-conventions).

## Nil Python

Nil Python calls imported C APIs directly through the same compiler backend. It
supports strict local type inference and automatic C-parameter return-lifting
(autotyping).

See the dedicated [Nil Python](./nil-python.md) page for detailed syntax, type
inference rules, and C-interop capabilities.

## The Frankonpiler part: cross-frontend interop

Pascal, C, and Nil Python are not three separate compilers glued together —
they lex and parse into the **same** AST/IR and register into the **same**
symbol table. A `uses` (Pascal) or `import` (Nil Python) resolves through one
shared unit-search chain that tries `.pas`/`.pp` first, then `.c`/`.h`, at
each search root. Whichever extension is found is parsed by that language's
own frontend and dropped into the same symbol table as everything already
compiled — no wrapper generation step, no IDL, no FFI declarations to hand-write.

### What works today

**Pascal reaching straight into a C header**, no Pascal wrapper unit written by
hand — `lib/pcl/gtk3.pas` does this for GTK3:

```pascal
uses gtk3_c;   { resolves to lib/pcl/gtk3_c.h — a plain C header }
```

**Nil Python importing a genuine Pascal unit** — `lib/rtl/re.pas` is a real
Pascal regex unit. `import re` in a `.npy`/`.py` file finds it through the same
resolver Pascal uses, once a same-directory `.py`/`.npy` module doesn't shadow
the name first:

```python
import re
```

**Nil Python calling a C library directly**, with return-lifting/autotyping
smoothing over `T**` out-parameters, string marshalling, and `#define` constant
mapping (see [architecture](../reference/architecture.md) for the mechanism):

```python
import sqlite3

db = sqlite3_open("/tmp/users.db")
sqlite3_exec(db, "CREATE TABLE users(id INT, name TEXT);", 0, 0, 0)
```

### What doesn't work yet

- **No C-to-Pascal direction.** The C frontend has no `uses`/`import`
  resolution at all — a `.c` file can only pull in other C headers, never a
  `.pas` unit. Interop from the C side has to go through Nil Python or Pascal
  calling C, not the reverse.
- **Pascal is deliberately blocked from finding `.py`/`.npy`.** A Pascal `uses`
  will never accidentally start pulling in Python-shaped source.
- **Namespace collisions are the sharp edge.** Because everything lands in one
  symbol table, a Pascal wrapper unit and a raw C package can want the same
  name (`uses zlib` — is that the hand-written Pascal binding or the C header
  directly?). There is no settled namespace syntax for "give me the C package,
  not the Pascal wrapper" yet.
- **No cross-frontend symbol mangling convention or type-mapping table.**
  Types that are frontend-specific (Pascal's managed `AnsiString`, for
  instance) don't cross the boundary uninterpreted — headers only expose
  plain pointers (`PChar`) across the C boundary, not a managed string type.
  A silent-bind hazard exists too: a C call can bind to a Pascal routine of a
  different arity without an error, so double-check signatures by hand at a
  language boundary rather than assuming it'll be caught.

These are open, tracked gaps (not implementation bugs to route around) — most
of the current cross-frontend friction is exactly here, in naming and library
boundaries, rather than in whether a call reaches the other language at all.

## Next

- [FPC compatibility](../language/fpc-compatibility.md)
- [Targets](./)
