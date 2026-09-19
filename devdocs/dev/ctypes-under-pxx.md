# ctypes under pxx — why we do not define it, and what defining it would cost

**Written 2026-09-19** from a conversation with the owner, who asked the
question this file is named after and then answered most of it himself. His
sentence is the spine of the document: *"we can just infer types, and still
compile, without dynamic typing."* That is correct, and it is a stronger claim
than it first looks — see "There is nothing to infer" below.

**Status: NOT a decision.** This is the measured ground for one. The fork is at
the end, stated in goal terms.

**Method, so a later reader can tell what has gone stale.** Compiler
`compiler/pascal26` sha256 `28067ea1d2f3...` at `440905dd2`. lekkerzeilen at
`74e6869`, That Space Program at `5d18097`. Every count below came from a
command; the commands are in the text. Read-only on both application trees —
nothing in this investigation wrote to either.

---

## 1. What ctypes is, mechanically

ctypes is a **runtime** FFI. In CPython:

- `CDLL("libSDL2.so")` is `dlopen`
- `lib.SDL_Init` is `dlsym`
- `lib.SDL_Init.restype = c_int` / `.argtypes = [c_uint]` attaches a signature
  **as data** to a callable object
- `lib.SDL_Init(flags)` builds an ABI-correct call frame **at call time** from
  that data — marshals each argument into the right register or stack slot per
  the target's calling convention, calls through a raw pointer, unmarshals the
  result

CPython does the last step with **libffi**. That is the only genuinely hard
part, and it is hard because the signature is not known until the program runs.

pxx's answer is the opposite end: `import "/usr/include/SDL2/SDL.h"` reads the
C header **at compile time** and emits a direct native call with a known
signature; the entry point links like any other C symbol. No dlopen, no
signature tables, no runtime resolution.

So the gap is not a missing module. It is that ctypes moves type information to
runtime and pxx's whole design moves it to compile time.

**There is no libffi in this tree** (`grep -rli 'libffi\|ffi_call' lib/ compiler/`
returns nothing) and there is no `mimic_ctypes` in `lib/rtl`.

---

## 2. There is nothing to infer — it is already a declaration

This is the owner's point and it is the most important paragraph here.

`lekkerzeilen/platform/_sdl2.py:223`:

```python
Init = _declare("SDL_Init", c_int, c_uint32)
```

That line is a **complete C prototype**: symbol name, return type, argument
types, all literal, at module top level. It is

```pascal
function SDL_Init(flags: LongWord): LongInt; cdecl; external;
```

written in Python. pxx does not have to *infer* a signature. The programmer
already declared one. pxx has to **read it and believe it**.

That reframes the job entirely. "Implement ctypes" sounds like reproducing
CPython's object model plus libffi. What the call sites actually contain is a
table of C prototypes in an unusual notation.

`_declare` itself (`_sdl2.py:211`) is not an obstacle:

```python
def _declare(name, restype, *argtypes):
    fn = getattr(lib, name)
    fn.restype = restype
    fn.argtypes = argtypes
    return fn
```

One-statement-per-line body, called with literals at every site, result bound to
a module-level name. That is the easy end of partial evaluation, not the hard
end. **This document said it was an obstacle in an earlier telling and that was
wrong** — the `getattr` takes a runtime string, but the string is a literal at
every call site, and nothing downstream needs the attribute lookup to have
happened, only the signature.

---

## 3. The lowering, and why it needs no libffi and no static linking

Pascal has **typed procedure variables**, and pxx has `lib/rtl/dynlibs.pas`
(`LoadLibrary`, `GetProcedureAddress`, `UnloadLibrary`, `GetProcAddress`,
`FreeLibrary`, `GetLoadErrorStr`). Put those together:

```pascal
var Init: function(flags: LongWord): LongInt; cdecl;
...
Init := GetProcedureAddress(h, 'SDL_Init');
```

**Signature known at compile time; address bound at runtime.** The call is a
direct native call through a pointer — the same thing a lazily-bound PLT does
on every dynamically linked program on the machine. No call-frame construction,
no libffi, no dynamic typing anywhere.

The consequence worth noticing: this does **not** force static linking. The
library can still be chosen at runtime, which matters — see §5.

Two tickets in `devdocs/progress/done/` are exactly this machinery, already
repaired: `bug-a-an-anonymous-procedural-type-is-not-accepted` and
`bug-p-a-procedural-type-cannot-return-an-array-or-another-procedural-type`.

---

## 4. The surface is small and closed

Both applications use nearly the identical set. Counted with
`grep -oh 'ctypes\.[A-Za-z_]*' <seam>/*.py | sort | uniq -c | sort -rn`:

| name | lekkerzeilen | TSP |
| --- | --- | --- |
| `c_uint` | 51 | 44 |
| `c_int` | 23 | 23 |
| `POINTER` | 16 | 14 |
| `byref` | 8 | 8 |
| `c_void_p` | 7 | 4 |
| `Structure` | 7 | 6 |
| `create_string_buffer` | 6 | 5 |
| `cast` | 6 | 6 |
| `c_char_p` | 5 | 4 |
| `util` | 4 | 4 |
| `c_float` | 4 | 5 |
| `CDLL` | 4 | 4 |
| `c_ubyte` | 3 | 4 |
| `c_ssize_t` | 3 | 3 |
| `c_char` | 2 | 1 |
| `CFUNCTYPE` | 1 | 1 |

Seventeen names. TSP's list matches because it copied the seam.

**It splits into two halves with very different prices:**

- **Layout** — `Structure`, `POINTER`, `cast`, `byref`, `create_string_buffer`,
  the `c_*` types. Records, pointers, sizes. pxx does all of this natively.
  `POINTER(c_int)` as an argtype is a `var` parameter.
- **Dynamic call** — `CDLL` + `restype`/`argtypes` + calling the result. This is
  the libffi-shaped half in CPython, and §3 is the reason it is not
  libffi-shaped here.

---

## 5. The two things that are genuinely dynamic

### 5a. Which library — and this is real logic, not incidental

`lekkerzeilen/platform/_sdl2.py:25-37` (and `_gl.py:16-28`, identical shape):

```python
for name in _CANDIDATES:
    try: return ctypes.CDLL(name)
    except OSError as exc: errors.append("%s: %s" % (name, exc))
found = ctypes.util.find_library("SDL2")
if found: return ctypes.CDLL(found)
raise OSError("SDL2 not found. Tried:\n  " + "\n  ".join(errors))
```

That copes with sonames differing across distributions and **tells the user what
it tried**. Lowering it to a `DT_NEEDED` on `libSDL2-2.0.so.0` trades
"try these three, then search, then explain" for "the dynamic loader fails
before `main` runs, naming one soname." For an application you hand to somebody
that is a downgrade, and it is the concrete reason §3's dlopen-plus-typed-
pointer shape is the right target rather than static linking.

`ctypes.util.find_library` then has to be written: the ldconfig cache plus the
standard directories. Ordinary library work, no design question in it.

Note pxx also has `weakexternal` (an undefined weak dynamic symbol; a library
reached only by weak imports emits no `DT_NEEDED`), which is the existing
mechanism for a genuinely optional library.

### 5b. Callbacks

`CFUNCTYPE` — one use in each application. A pointer going the **other**
direction: C calling back into your code. That needs a thunk generated per
signature, and it is the one place in either seam where something really must be
built at runtime. Everything else on the list is recognition.

---

## 6. What this is costing today

Nothing in `tsp/` or the parts of lekkerzeilen above the seam knows which runtime
it is on. The seam chooses, in `platform/__init__.py`:

```python
try:
    import ctypes
except ImportError:
    from . import _pxx as _backend      # pxx
else:
    from . import _ctypes_backend as _backend   # CPython
```

The discriminator is **the runtime's own answer to `import ctypes`**. No flag,
no version sniff. Two pxx-shaped details in there are deliberate and documented
in the file: the backend is bound as a *unit alias* rather than returned from a
function (a module is a unit, and a unit is not a first-class value under pxx),
and the `else:` is load-bearing — it keeps the ctypes-side import out of the
`try`'s exception coverage so an `ImportError` raised *inside* the backend
propagates instead of being swallowed as "no ctypes on this runtime".

**lekkerzeilen paid for the missing ctypes with a hand-written second backend.**

| file | lines |
| --- | --- |
| `platform/_pxx.py` | **974** |
| `platform/_ctypes_backend.py` | 327 |
| `platform/__init__.py` | 135 |

The pxx arm is 3x the ctypes arm, and the excess is precisely the work ctypes
was doing. `_pxx.py` carries a hand-derived offset table
(`_OFF_KEY_SYM = 20`, `_OFF_MOTION_XREL = 28`, … at lines 53-71) whose own
docstring says the offsets came from `offsetof` in a C program compiled by GCC
against this machine's SDL2 headers, that they are x86-64 SysV, and that **a
port to another ABI must re-derive every one the same way**. Its `poll()` says
why: *"The ctypes backend casts the buffer to the right event struct per kind.
There is no cast here, so each field is read at its offset instead."*

A layout-only shim — `Structure` + `cast` + `POINTER` and nothing else — deletes
that whole table on every target while leaving the calls native. That is the
cheapest useful increment and it is worth naming separately from the rest.

**That Space Program has not paid yet.** Its `except ImportError:` does not fall
back; it raises, pointing at lekkerzeilen:

```python
raise ImportError("tsp.platform: no ctypes on this runtime and the PXX "
                  "backend is not ported yet (see this module's docstring)")
```

and the docstring says *"Copy and adapt it from there when TSP starts targeting
PXX; the surface below was kept identical in shape so that is a translation, not
a redesign."*

**Measured consequence, 2026-09-19.** Compiling lekkerzeilen's seam module by
module under the flags its own `_pxx.py` docstring prescribes
(`-dSDL_DISABLE_IMMINTRIN_H -dGL_GLEXT_PROTOTYPES`):

```
__init__.py          PASS
_vocab.py            PASS
_pxx.py              PASS
_ctypes_backend.py   pascal26:8:  error: import: no unit named ctypes ...
_gl.py               pascal26:9:  error: import: no unit named ctypes ...
_sdl2.py             pascal26:10: error: import: no unit named ctypes ...
```

**The three failures are exactly the CPython arm — the branch pxx is designed
never to take.** Every module pxx actually reaches compiles. Any module count
quoted for lekkerzeilen that includes those three is using the wrong
denominator; this seat has quoted "36 of 39" and that is the error in it.

On the TSP side the same structure produces
`tsp/platform/__init__.py :: undefined variable (_backend)` — the `except` arm
raises, `_backend` is never bound, and the four modules reading it go undefined.
Not a compiler bug and not a missing shim: the application is saying the port is
not written.

---

## 7. Why it has not been done

**There is no decision against it and no ticket asking for it.** What exists is
an analysis that already reached this conclusion and has been sitting unowned:

`devdocs/progress/unfinished/feature-nilpy-thirdparty-libraries-as-targets.md`,
`prio: 65`, `status: unfinished`, `owner: unassigned`. Its classification table,
row 2:

> **ctypes / cffi** — pure Python that `dlopen`s an ordinary C library. No
> `Python.h` anywhere → *compile the C library with cfront, bind natively.*
> **"Cheap, and it is the case pxx is unusually good at."**

Two reasons it stayed unowned, and the second is the interesting one:

1. **The name misleads.** "ctypes" reads as "reproduce CPython's ctypes", which
   means libffi and an object model — a large Track A project nobody starts on a
   whim. What the call sites contain is a prototype table. This is this
   project's own *the name is not the thing* arriving in a design decision
   rather than in a constant.
2. **`_pxx.py` removed the pressure.** Once 974 hand-written lines worked, the
   reason to define ctypes went away. The workaround became the solution, and
   the cost moved to the next application — which has not paid it and currently
   cannot run under pxx at all.

**The mechanism for "the frontend defines a module" already exists and is in
daily use.** `compiler/pyparser.inc:13811` onward is a literal table:

```pascal
else if dotted = 'math.atan2' then Result := 'ArcTan2'
else if dotted = 'math.sqrt'  then Result := 'Sqrt'
```

`math` is not a library we ship. It is a vocabulary the frontend understands,
mapped onto things that already exist. ctypes is the same shape of problem,
larger.

---

## 8. What was NOT measured

Stated plainly because the argument above is only as good as its population.

- **The population is two seams in two applications, both written by the owner,
  both in the same house style.** Every `restype`/`argtypes` in them is literal
  at the call site. A third-party library may build signatures in a loop, or
  call an undeclared symbol and rely on ctypes' default argument conversions —
  neither of which can be lowered. **Nothing here establishes "always".**
- No prototype was actually lowered. §3 is a design claim resting on two
  mechanisms that exist separately (typed procedure variables; `dynlibs.pas`),
  not on a built example.
- `ctypes.util.find_library` and `CFUNCTYPE` are named as work, not sized.
- The layout-only increment (§6) is asserted to delete the offset table. That
  follows from reading `_pxx.py`, not from building it.

---

## 9. The hazard to handle in the same commit

**The day any `mimic_ctypes` lands — even a layout-only one — `import ctypes`
starts succeeding, and both applications silently switch off their pxx backend
onto the CPython arm.** lekkerzeilen's 974-line working backend stops being
reached; TSP's raise stops firing and it takes a path whose other three modules
do not compile.

The selector keys off absence, and we would be removing the absence. Whoever
lands a ctypes shim owns that switch in the same commit — either by making the
pxx arm assert on something only pxx has rather than infer from something only
CPython has, or by changing the seam in both applications at the same time.

`no unit named ctypes` is currently the top wall on TSP's platform arm (3
modules), which makes ctypes the natural next shim for somebody who has not read
this file.

---

## 10. The fork, in goal terms

**Do we want programs written against ctypes to run under pxx, or do we want
programs to reach C through pxx's own header import and keep ctypes as CPython's
business?**

- **Keep it CPython's business.** Nothing changes. Every application that wants
  pxx writes a `_pxx.py`. Price observed: 974 lines for one application, an
  unported seam for the second, and an ABI-specific offset table per target.
- **Define it.** The declarations are already in the source; §3 is the lowering;
  §5 is the genuinely dynamic residue. Cheapest useful increment is the layout
  half alone (§4), which deletes the offset table and leaves the calls native.
  §9 comes with it, unconditionally.

Cost is not the fork — both are affordable. The fork is whether a ctypes-shaped
program is something pxx runs, or something pxx asks you to rewrite.
