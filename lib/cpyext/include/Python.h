/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CPYEXT_PYTHON_H
#define PXX_CPYEXT_PYTHON_H 1

/* pxx's own `Python.h` — enough of the CPython C-API's SOURCE-LEVEL surface
 * for a plain C extension module's source to compile unmodified against it
 * (see lib/cpyext/README.md and
 * devdocs/progress/working/feature-nilpy-cpyext-c-api-from-source.md).
 *
 * NOT ABI-compatible with real CPython: `PyObject` here is pxx's own small
 * tagged-object model, not CPython's. A prebuilt CPython .so cannot be
 * loaded against this header — only extension SOURCE compiled by cfront.
 *
 * M1 ("hello-ext") added: a one-int-argument, one-int-return function exposed
 * through a real PyModuleDef/PyMethodDef table and PyInit_<name>.
 * M2 ("arguments and errors") added: PyArg_ParseTuple/Py_BuildValue for
 * "i l d s s# O", plus PyErr_SetString/PyErr_Occurred/PyErr_Clear so an
 * extension's error propagates into a NilPy `except`.
 * M3 ("strings and containers") added: PyBytes_* (a str-distinct type), and
 * PyList_* / PyDict_* construction + iteration (PyDict_Next), plus 'y'/'y#'
 * bytes format letters for PyArg_ParseTuple/Py_BuildValue. Scope note: M3's
 * containers are built and consumed ENTIRELY inside the extension's own C
 * code (its PyMethodDef entry points still cross the NilPy boundary only as
 * scalars/strings, same as M1/M2) — they do NOT yet round-trip as native
 * NilPy list/dict Variants. That deeper integration is `compiler/builtin/
 * pylib.pas` work the ticket calls out separately ("PyObject* handles
 * resolving to NilPy variants/objects") and is left for a later milestone;
 * see the M3 note in the ticket file for the full reasoning.
 * M4 ("a real extension") added: the slice MarkupSafe's `_speedups.c` (a
 * real, unmodified, vendored PyPI extension — see
 * test/nilpy_units/vendor/markupsafe_speedups.c) needs: PyUnicode_Check,
 * PyUnicode_READY (no-op — nothing to "ready" in this runtime),
 * PyUnicode_KIND/1BYTE_DATA/2BYTE_DATA/4BYTE_DATA/GET_LENGTH/IS_ASCII,
 * PyUnicode_New, Py_UCS1/2/4, METH_O, PyModuleDef's `m_slots` field +
 * PyModuleDef_Slot + PyModuleDef_Init (multi-phase init collapsed to
 * single-phase — see the comment on PyModuleDef_Init). This runtime's
 * strings are byte-oriented only (no wide-Unicode kind2/kind4 storage), so
 * PyUnicode_KIND always reports PyUnicode_1BYTE_KIND — kind2/kind4 code
 * paths in vendored source still compile (so linking stays honest) but are
 * never exercised.
 * Grow this header only as a later milestone's extension needs more surface;
 * an API this header does not implement should fail to LINK (undefined
 * symbol), never silently do nothing at runtime.
 */

#include <stdarg.h>
#include <stddef.h>
#include <assert.h> /* real CPython's Python.h pulls this in transitively too —
                        MarkupSafe's _speedups.c calls assert() without its own
                        #include, relying on exactly that */

/* --- version identity ---------------------------------------------------
 * Real CPython's Python.h defines `Py_PYTHON_H` and the PY_*_VERSION family,
 * and generated / vendored extension source gates on them BEFORE it emits a
 * single line. Cython's output is the extreme case:
 *
 *     #include "Python.h"
 *     #ifndef Py_PYTHON_H
 *         #error Python headers needed ...
 *     #elif PY_VERSION_HEX < 0x03080000
 *         #error Cython requires Python 3.8+.
 *     #else
 *         ...the entire module...
 *     #endif
 *
 * Without these, that `#elif` is true and the whole module body is excluded —
 * and because cfront currently drops `#error` silently
 * (bug-cfront-error-directive-silently-ignored) the file appears to compile.
 *
 * The version claimed here is a SOURCE-LEVEL claim only ("the API surface this
 * header offers is shaped like 3.12's"), never an ABI one — see the header
 * note above. It is deliberately a single place to turn: which minor version
 * we claim decides which of Cython's many `#if PY_VERSION_HEX` paths the
 * generated code takes, so it is a knob for the cpyext milestones to tune with
 * measurements, not a fact about this runtime. */
#define Py_PYTHON_H 1
#define PY_MAJOR_VERSION  3
#define PY_MINOR_VERSION  12
#define PY_MICRO_VERSION  0
#define PY_RELEASE_LEVEL  0xF   /* final */
#define PY_RELEASE_SERIAL 0
#define PY_VERSION_HEX ((PY_MAJOR_VERSION << 24) | \
                        (PY_MINOR_VERSION << 16) | \
                        (PY_MICRO_VERSION <<  8) | \
                        (PY_RELEASE_LEVEL <<  4) | \
                        (PY_RELEASE_SERIAL))
#define PY_VERSION "3.12.0"

typedef long Py_ssize_t;
#define PY_SSIZE_T_MAX ((Py_ssize_t)(((unsigned long)-1) >> 1))
#define PY_SSIZE_T_MIN (-PY_SSIZE_T_MAX - 1)

/* Spellings CPython's headers provide and generated code uses in casts and
 * conversion helpers. `LONG_LONG` is CPython's own legacy alias, not limits.h's
 * LLONG_MAX family — the two are unrelated despite the name. */
/* MACROS, not typedefs, exactly as CPython spells them — generated code writes
 * `unsigned PY_LONG_LONG`, which only parses if the name expands to a type
 * KEYWORD sequence. A typedef compiles here and then fails at every such use. */
#define LONG_LONG long long
#define PY_LONG_LONG long long
#define PY_INT64_T long long
typedef Py_ssize_t Py_hash_t;
typedef unsigned long Py_uhash_t;

/* Runtime version, as `PyLong`-free plain integer. Real CPython exposes it as
 * a `const unsigned long`; generated code compares it against PY_VERSION_HEX
 * to detect a build/runtime mismatch, which for us can never differ. */
#define Py_Version ((unsigned long)PY_VERSION_HEX)

/* Vectorcall. Since M5b this runtime DOES honour the protocol, but only the
 * limited-API half of it: a heap type declares where its vectorcall pointer
 * lives by putting a `__vectorcalloffset__` entry in its Py_tp_members table
 * (see PyType_FromMetaclass), and PyVectorcall_Call reads the slot from there.
 * The flag bit below is still never SET by this runtime — nothing here hands
 * out a borrowable argument-vector prefix — so the mask stays a no-op. */
#define PY_VECTORCALL_ARGUMENTS_OFFSET \
    ((size_t)1 << (8 * sizeof(size_t) - 1))

/* Py_CompileString / PyEval_EvalCode start symbols. Declared for the same
 * reason: they appear in generated utility code that a compiled-ahead-of-time
 * extension never reaches. There is no compiler in this runtime, and anything
 * that actually calls them will fail at LINK with its own name — which is the
 * intended failure mode (see the header note on honest promises). */
#define Py_single_input 256
#define Py_file_input   257
#define Py_eval_input   258

/* Code-object flags. CPython puts these in <compile.h> and does NOT expose
 * them under Py_LIMITED_API, which is why generated code has a fallback that
 * imports the `inspect` module and reads them as attributes at run time. No
 * runtime without an importer can satisfy that fallback, so this header
 * DELIBERATELY diverges and defines them unconditionally: they are fixed,
 * published constants, not machinery, and defining them is what keeps a
 * Cython module's init from needing a live `inspect`.
 *
 * <compile.h> re-states them for source that includes it directly; the two
 * must agree, hence the header guard there. */
#ifndef CO_OPTIMIZED
#define CO_OPTIMIZED            0x0001
#define CO_NEWLOCALS            0x0002
#define CO_VARARGS              0x0004
#define CO_VARKEYWORDS          0x0008
#define CO_NESTED               0x0010
#define CO_GENERATOR            0x0020
#define CO_NOFREE               0x0040
#define CO_COROUTINE            0x0080
#define CO_ITERABLE_COROUTINE   0x0100
#define CO_ASYNC_GENERATOR      0x0200
#endif

/* --- object model -------------------------------------------------------
 * One tagged struct standing in for every PyObject subtype M1 needs. Real
 * CPython objects vary in size per type with a common PyObject header; pxx's
 * own extension ecosystem never inspects the layout directly (an extension
 * only ever holds a PyObject*), so one fixed-size struct is enough here. */

#define PYOBJ_NONE   0
#define PYOBJ_LONG   1
#define PYOBJ_TUPLE  2
#define PYOBJ_MODULE 3
#define PYOBJ_FLOAT  4
#define PYOBJ_STR    5
#define PYOBJ_BYTES  6
#define PYOBJ_LIST   7
#define PYOBJ_DICT   8
/* M5b: a builtin-function object (ob_ptr = its PyMethodDef*) and a plain
 * attribute namespace (a module, or the module SPEC the import machinery
 * normally supplies). Both keep their attributes in ob_attrs. */
#define PYOBJ_CFUNC  9
#define PYOBJ_NS    10
/* M5b: a type object (PyTypeObject, whose own first member is this header)
 * and an INSTANCE of one. An instance's storage is tp_basicsize bytes that the
 * EXTENSION lays out — this header sits at offset 0 and everything past it
 * belongs to the extension's own struct, which is exactly the contract
 * `PyObject_HEAD` promises and what offsetof() in a member table measures. */
#define PYOBJ_TYPE  11
#define PYOBJ_INST  12

typedef struct _object {
    long   ob_refcnt;
    int    ob_kind;   /* PYOBJ_* above */
    long   ob_ival;   /* PYOBJ_LONG payload;
                          PYOBJ_CFUNC: the `self` this builtin method is bound
                          to, held as an OWNED reference and released with the
                          method object. PyCFunction_GetSelf hands it back
                          BORROWED, exactly as CPython's does.
                          Owning it is deliberate and it costs something:
                          Cython's function object owns its PyCFunction and
                          passes ITSELF as self, so the pair is a cycle that
                          this runtime — having no cycle collector — never
                          reclaims. Real CPython has the identical cycle and
                          pays for it with its GC (which is why CyFunction
                          carries Py_TPFLAGS_HAVE_GC and a traverse slot). The
                          alternative, a borrowed self, trades a bounded leak
                          for a dangling pointer the moment any bound method
                          outlives its receiver — a silent wrong answer, which
                          is the one thing this runtime will not do. */
    double ob_fval;   /* PYOBJ_FLOAT payload */
    void  *ob_ptr;    /* PYOBJ_TUPLE/PYOBJ_LIST: PyObject** items;
                          PYOBJ_MODULE: PyMethodDef*;
                          PYOBJ_CFUNC: PyMethodDef* (the one entry);
                          PYOBJ_STR/PYOBJ_BYTES: char* bytes (NUL-terminated);
                          PYOBJ_DICT: PyDictEntry* pairs;
                          PYOBJ_TYPE/PYOBJ_INST: this object's PyTypeObject*
                          (for a type that is its METAtype). This is where the
                          `ob_type` of real CPython lives — reusing the field
                          rather than adding one keeps every other kind the
                          same size, and Py_TYPE is the only reader. */
    long   ob_size;   /* PYOBJ_TUPLE/PYOBJ_LIST: item count;
                          PYOBJ_MODULE: method count;
                          PYOBJ_STR/PYOBJ_BYTES: byte length (excl. the NUL);
                          PYOBJ_DICT: pair count */
    struct _object *ob_attrs; /* PYOBJ_MODULE/PYOBJ_NS/PYOBJ_CFUNC: the
                          attribute dict, allocated on first use. NULL on every
                          other kind — this model has no per-instance
                          attributes, and PyObject_GetAttr says so (M5b). */
} PyObject;

typedef struct PyDictEntry {
    PyObject *key;
    PyObject *value;
} PyDictEntry;

extern PyObject _Py_NoneStruct;
#define Py_None (&_Py_NoneStruct)

void Py_IncRef(PyObject *o);
void Py_DecRef(PyObject *o);
#define Py_INCREF(o)  Py_IncRef((PyObject *)(o))
#define Py_DECREF(o)  Py_DecRef((PyObject *)(o))
#define Py_XINCREF(o) do { if ((o) != 0) Py_IncRef((PyObject *)(o)); } while (0)
#define Py_XDECREF(o) do { if ((o) != 0) Py_DecRef((PyObject *)(o)); } while (0)
#define Py_CLEAR(o)   do { PyObject *_pxx_tmp = (PyObject *)(o); \
                           if (_pxx_tmp != 0) { (o) = 0; Py_DecRef(_pxx_tmp); } } while (0)

/* The canonical True/False objects. Real CPython exposes struct instances and
 * `Py_True`/`Py_False` as their addresses; this runtime has no bool object
 * kind yet, so they are the two long objects 1 and 0 — enough for the
 * `return o == Py_True` / `Py_INCREF(Py_False); return Py_False;` shapes
 * generated code emits, and honest about being nothing more. */
extern PyObject _Py_TrueStruct;
extern PyObject _Py_FalseStruct;
#define Py_True  (&_Py_TrueStruct)
#define Py_False (&_Py_FalseStruct)

/* PEP 380 send() protocol result. No generators cross this boundary — the
 * enum exists because generated code typedefs a function pointer returning it
 * before any feature test can exclude the declaration. */
typedef enum {
    PYGEN_RETURN = 0,
    PYGEN_ERROR = -1,
    PYGEN_NEXT = 1
} PySendResult;

/* Rich-comparison opcodes (PyObject_RichCompare / _RichCompareBool). */
#define Py_LT 0
#define Py_LE 1
#define Py_EQ 2
#define Py_NE 3
#define Py_GT 4
#define Py_GE 5

/* --- M5b: type objects with real slots -----------------------------------
 *
 * Through M5a a PyTypeObject was a tp_name and nothing else: identity only,
 * enough for `Py_TYPE(o) == &PyDict_Type`. Cython's CyFunction (what
 * `-X binding=False` used to suppress) needs the real thing — a HEAP type
 * built from a PyType_Spec, carrying tp_call, tp_descr_get, a member table
 * and a getset table, with instances whose storage the extension lays out.
 *
 * So a type object is now itself a PyObject (`ob_base`, kind PYOBJ_TYPE),
 * which is what makes `PyTuple_Pack(1, &PyType_Type)`, `Py_DECREF(cached_type)`
 * and `PyObject_GetAttrString(t, "__basicsize__")` mean something. Types in
 * this runtime are IMMORTAL: the static ones are process-global, and heap
 * types are cached in Cython's shared-ABI module for the life of the program,
 * so nothing ever frees one and Py_DecRef leaves them alone.
 *
 * What this deliberately does NOT bring: inheritance. `tp_base` is recorded
 * and walked by PyObject_TypeCheck, but no slot is INHERITED from a base and
 * there is no MRO, no metaclass dispatch, and no user subclassing. Every type
 * that exists here is either a builtin or built whole from one spec, and that
 * is exactly what the limited API's own contract asks of an extension. */

/* The callable shapes a slot table is built out of. Plain C typedefs, named
 * as CPython names them because the generated code casts through them. */
typedef PyObject *(*unaryfunc)(PyObject *o);
typedef PyObject *(*binaryfunc)(PyObject *a, PyObject *b);
typedef PyObject *(*ternaryfunc)(PyObject *a, PyObject *b, PyObject *c);
typedef int (*inquiry)(PyObject *o);
typedef Py_ssize_t (*lenfunc)(PyObject *o);
typedef int (*visitproc)(PyObject *o, void *arg);
typedef int (*traverseproc)(PyObject *o, visitproc visit, void *arg);
typedef void (*destructor)(PyObject *o);
typedef void (*freefunc)(void *p);
typedef PyObject *(*reprfunc)(PyObject *o);
typedef Py_hash_t (*hashfunc)(PyObject *o);
typedef PyObject *(*getattrofunc)(PyObject *o, PyObject *name);
typedef int (*setattrofunc)(PyObject *o, PyObject *name, PyObject *v);
typedef PyObject *(*richcmpfunc)(PyObject *a, PyObject *b, int op);
typedef PyObject *(*getiterfunc)(PyObject *o);
typedef PyObject *(*iternextfunc)(PyObject *o);
typedef PyObject *(*descrgetfunc)(PyObject *o, PyObject *obj, PyObject *type);
typedef int (*descrsetfunc)(PyObject *o, PyObject *obj, PyObject *v);
typedef int (*initproc)(PyObject *o, PyObject *args, PyObject *kwargs);
typedef PyObject *(*getter)(PyObject *o, void *closure);
typedef int (*setter)(PyObject *o, PyObject *v, void *closure);
/* The vectorcall entry point. An object does not carry a POINTER to its
 * vectorcall function in any fixed place — its type says where, via the
 * `__vectorcalloffset__` member entry (limited-API rule). */
typedef PyObject *(*vectorcallfunc)(PyObject *callable, PyObject *const *args,
                                    size_t nargsf, PyObject *kwnames);

typedef struct PyGetSetDef {
    const char *name;
    getter      get;
    setter      set;
    const char *doc;
    void       *closure;
} PyGetSetDef;

/* Slot ids: CPython's own numbering (Include/typeslots.h), not a private
 * scheme. Only the ids this runtime actually consults are listed — an id we do
 * not name cannot appear in a spec, because the spec is written against THIS
 * header, so an unnamed one is a compile error rather than a silent no-op. */
#define Py_tp_base       48
#define Py_tp_call       50
#define Py_tp_clear      51
#define Py_tp_dealloc    52
#define Py_tp_descr_get  54
#define Py_tp_descr_set  55
#define Py_tp_getattro   58
#define Py_tp_hash       59
#define Py_tp_init       60
#define Py_tp_iter       62
#define Py_tp_iternext   63
#define Py_tp_methods    64
#define Py_tp_new        65
#define Py_tp_repr       66
#define Py_tp_richcompare 67
#define Py_tp_setattro   69
#define Py_tp_str        70
#define Py_tp_traverse   71
#define Py_tp_members    72
#define Py_tp_getset     73

/* Type flags. Same bit positions as CPython so a value that crosses the
 * boundary (a spec's flags word, PyType_GetFlags' result) means the same
 * thing on both sides. Py_TPFLAGS_DEFAULT is 3.12's value. */
#define Py_TPFLAGS_HEAPTYPE          (1UL << 9)
#define Py_TPFLAGS_BASETYPE          (1UL << 10)
#define Py_TPFLAGS_HAVE_GC           (1UL << 14)
#define Py_TPFLAGS_DEFAULT           (1UL << 18)
#define Py_TPFLAGS_UNICODE_SUBCLASS  (1UL << 28)

typedef struct PyType_Slot {
    int   slot;
    void *pfunc;
} PyType_Slot;

typedef struct PyType_Spec {
    const char   *name;
    int           basicsize;
    int           itemsize;
    unsigned int  flags;
    PyType_Slot  *slots;       /* terminated by slot == 0 */
} PyType_Spec;

typedef struct _typeobject {
    PyObject      ob_base;     /* kind PYOBJ_TYPE; ob_ptr is the METAtype */
    const char   *tp_name;     /* dotted, as the spec gives it */
    Py_ssize_t    tp_basicsize;
    Py_ssize_t    tp_itemsize;
    unsigned long tp_flags;
    PyType_Slot  *tp_slots;    /* BORROWED from the spec, which is static */
    struct _typeobject *tp_base;
    /* Where an instance keeps these, in bytes from the object's start. 0 means
     * "this type has none". Filled in from the type's own Py_tp_members table:
     * __dictoffset__, __weaklistoffset__, __vectorcalloffset__ — the limited
     * API's way of declaring them, and the only way available to a spec. */
    Py_ssize_t    tp_dictoffset;
    Py_ssize_t    tp_weaklistoffset;
    Py_ssize_t    tp_vectorcall_offset;
} PyTypeObject;

/* Declared after PyTypeObject because they name it. */
typedef PyObject *(*newfunc)(PyTypeObject *t, PyObject *args, PyObject *kwargs);
typedef PyObject *(*allocfunc)(PyTypeObject *t, Py_ssize_t nitems);
/* METH_METHOD's calling convention: like fastcall-with-keywords, plus the
 * class the method was defined on. */
typedef PyObject *(*PyCMethod)(PyObject *self, PyTypeObject *defining_class,
                               PyObject *const *args, size_t nargs,
                               PyObject *kwnames);

/* `PyObject_HEAD` is what an extension writes at the top of its own instance
 * struct, and it must be the WHOLE header — offsetof() past it is what the
 * member table publishes, so anything less would misplace every field. */
#define PyObject_HEAD PyObject ob_base;
#define PyObject_VAR_HEAD PyObject ob_base;

/* M5a: the built-in type objects generated code compares against
 * (`Py_TYPE(o) == &PyDict_Type`). One PyTypeObject per PYOBJ_* kind lives in
 * the runtime; these are those entries by name. They carry no slots — a
 * builtin's behaviour is in the PyLong_* / PyDict_* functions, not behind a
 * slot table — so `tp_name` and identity remain all they mean. */
extern PyTypeObject PyLong_Type;
extern PyTypeObject PyFloat_Type;
extern PyTypeObject PyUnicode_Type;
extern PyTypeObject PyBytes_Type;
extern PyTypeObject PyTuple_Type;
extern PyTypeObject PyList_Type;
extern PyTypeObject PyDict_Type;
/* `type` itself: generated code passes `&PyType_Type` as the base of a
 * metaclass built from a spec. */
extern PyTypeObject PyType_Type;
PyTypeObject *Py_TYPE(PyObject *o);

/* Building a heap type. PyType_FromMetaclass is the 3.12 entry point and the
 * one Cython uses under Py_LIMITED_API >= 0x030C0000; the older spellings are
 * the same call with fewer arguments. `metaclass` and `bases` are honoured
 * only as far as this model goes: the metaclass becomes the new type's
 * Py_TYPE, and the first base becomes tp_base — no slot is inherited through
 * either, per the "no inheritance" note above. */
PyObject *PyType_FromMetaclass(PyTypeObject *metaclass, PyObject *module,
                               PyType_Spec *spec, PyObject *bases);
PyObject *PyType_FromModuleAndSpec(PyObject *module, PyType_Spec *spec,
                                   PyObject *bases);
PyObject *PyType_FromSpecWithBases(PyType_Spec *spec, PyObject *bases);
PyObject *PyType_FromSpec(PyType_Spec *spec);

void *PyType_GetSlot(PyTypeObject *t, int slot);
unsigned long PyType_GetFlags(PyTypeObject *t);
int PyType_HasFeature(PyTypeObject *t, unsigned long feature);
void PyType_Modified(PyTypeObject *t);
int PyType_Check(PyObject *o);
int PyType_CheckExact(PyObject *o);
int PyType_IsSubtype(PyTypeObject *a, PyTypeObject *b);
int PyObject_TypeCheck(PyObject *o, PyTypeObject *t);

/* --- M5b: instances, and the GC that is not there -------------------------
 * Allocation is by TYPE: tp_basicsize zeroed bytes with this header at offset
 * 0. `PyObject_GC_New` is spelled as CPython spells it (a macro taking the C
 * struct type, so the result is already the right pointer type).
 *
 * There is no cycle collector here YET — the runtime is plain refcounting — so
 * tracking is a no-op and Py_VISIT never runs. They are NOT stubs that hide a
 * problem: an uncollected cycle is a leak, and a leak in a module-level
 * function object that lives as long as the process is not observable.
 *
 * "Not yet" is sequencing, not a design stance. The project's GC decision
 * (devdocs/developer/garbage-collection-thoughts.md, point 4) reserves cycle
 * collection as the one legitimate niche ARC cannot cover, and everything a
 * collector would need is already in reach: each heap type Cython builds
 * carries Py_tp_traverse and Py_tp_clear, PyType_GetSlot already returns them,
 * and Py_VISIT already expands correctly — they are simply never called. What
 * is missing is a tracked-object list and the trial-deletion pass. Scoped in
 * feature-nilpy-cpyext-cycle-collector; it starts to matter at M5c, where a
 * cdef class allocates instances in a loop.
 */
PyObject *_PyObject_NewFromType(PyTypeObject *t);
#define PyObject_GC_New(TYPE, typeobj) ((TYPE *)_PyObject_NewFromType(typeobj))
#define PyObject_New(TYPE, typeobj)    ((TYPE *)_PyObject_NewFromType(typeobj))
void PyObject_GC_Del(void *op);
void PyObject_GC_Track(void *op);
void PyObject_GC_UnTrack(void *op);
void PyObject_ClearWeakRefs(PyObject *o);
/* CPython's own definition, verbatim in effect: it expands inside a
 * traverseproc where `visit` and `arg` are in scope. Never executed here
 * because nothing calls a traverse slot, but it must compile and it must not
 * walk a null. */
#define Py_VISIT(o) \
    do { \
        if ((o) != 0) { \
            int _pxx_vret = visit((PyObject *)(o), arg); \
            if (_pxx_vret != 0) return _pxx_vret; \
        } \
    } while (0)

/* Vectorcall over a type that published a `__vectorcalloffset__`. This is the
 * whole reason the member table is parsed: it is the only channel the limited
 * API gives a spec for saying where the function pointer lives. */
PyObject *PyVectorcall_Call(PyObject *callable, PyObject *args, PyObject *kwargs);

/* Instance __dict__, at tp_dictoffset. Used directly as the func_dict/__dict__
 * getset pair in Cython's CyFunction, which is why they are public. */
PyObject *PyObject_GenericGetDict(PyObject *o, void *context);
int PyObject_GenericSetDict(PyObject *o, PyObject *v, void *context);

/* --- int / float / string conversion -------------------------------------- */
PyObject *PyLong_FromLong(long v);
long PyLong_AsLong(PyObject *o);

PyObject *PyFloat_FromDouble(double v);
double PyFloat_AsDouble(PyObject *o);

PyObject *PyUnicode_FromString(const char *s);
PyObject *PyUnicode_FromStringAndSize(const char *s, Py_ssize_t n);
const char *PyUnicode_AsUTF8(PyObject *o);

/* --- unicode "kind" internals (M4) ----------------------------------------
 * Real CPython stores a string at whichever of 3 widths (1/2/4 bytes per
 * char) fits its widest codepoint; this runtime only ever stores bytes, so
 * PyUnicode_KIND is always PyUnicode_1BYTE_KIND and only *_1BYTE_DATA is
 * ever live. The 2BYTE/4BYTE declarations exist so vendored source that
 * mentions them still compiles and links (dead code on this runtime, never
 * reached because KIND never reports those kinds). */
typedef unsigned char  Py_UCS1;
typedef unsigned short Py_UCS2;
typedef unsigned int   Py_UCS4;

/* Real CPython gives PyUnicodeObject its own layout (PyObject header +
 * unicode-specific fields); this runtime's PyObject already carries
 * everything a string needs, so PyUnicodeObject is just an alias — enough
 * for vendored source's `(PyUnicodeObject *)` casts and parameter types. */
typedef PyObject PyUnicodeObject;

#define PyUnicode_1BYTE_KIND 1
#define PyUnicode_2BYTE_KIND 2
#define PyUnicode_4BYTE_KIND 4

int PyUnicode_Check(PyObject *o);
int PyUnicode_READY(PyObject *o); /* always succeeds (0); nothing to ready */
int PyUnicode_KIND(PyObject *o);  /* always PyUnicode_1BYTE_KIND here */
Py_UCS1 *PyUnicode_1BYTE_DATA(PyObject *o);
Py_UCS2 *PyUnicode_2BYTE_DATA(PyObject *o); /* never actually reached */
Py_UCS4 *PyUnicode_4BYTE_DATA(PyObject *o); /* never actually reached */
Py_ssize_t PyUnicode_GET_LENGTH(PyObject *o);
int PyUnicode_IS_ASCII(PyObject *o);
/* size = length in CODE UNITS of the kind maxchar implies; since this
 * runtime is byte-only, size is always treated as a byte count regardless
 * of maxchar (accurate for the only kind we ever produce). Returns a
 * NEW reference to a mutable buffer the caller fills via *_1BYTE_DATA. */
PyObject *PyUnicode_New(Py_ssize_t size, Py_UCS4 maxchar);

/* --- bytes: like PyUnicode_* but a distinct type (PYOBJ_BYTES) ---------- */
PyObject *PyBytes_FromStringAndSize(const char *s, Py_ssize_t n);
char *PyBytes_AsString(PyObject *o);
Py_ssize_t PyBytes_Size(PyObject *o);

/* --- tuples: enough to carry PyArg_ParseTuple's positional args --------- */
PyObject *PyTuple_New(Py_ssize_t n);
int PyTuple_SetItem(PyObject *t, Py_ssize_t i, PyObject *v); /* steals v */
PyObject *PyTuple_GetItem(PyObject *t, Py_ssize_t i);        /* borrowed */

/* --- lists: growable, index-settable/gettable, appendable --------------- */
PyObject *PyList_New(Py_ssize_t n);
int PyList_SetItem(PyObject *l, Py_ssize_t i, PyObject *v); /* steals v */
PyObject *PyList_GetItem(PyObject *l, Py_ssize_t i);        /* borrowed */
int PyList_Append(PyObject *l, PyObject *v);                /* does NOT steal */
Py_ssize_t PyList_Size(PyObject *l);

/* --- dicts: linear-scan association (fine at extension/test scale) ------
 * Key equality: PYOBJ_LONG by value, PYOBJ_STR/PYOBJ_BYTES by content,
 * everything else by identity. PyDict_Next mirrors the real API's
 * incremental-iterator shape: seed *ppos = 0, call in a loop until it
 * returns 0; borrowed key/value, *ppos advances one pair per call. */
PyObject *PyDict_New(void);
int PyDict_SetItem(PyObject *d, PyObject *key, PyObject *value); /* does NOT steal */
PyObject *PyDict_GetItem(PyObject *d, PyObject *key);            /* borrowed, or NULL */
Py_ssize_t PyDict_Size(PyObject *d);
int PyDict_Next(PyObject *d, Py_ssize_t *ppos, PyObject **pkey, PyObject **pvalue);

/* --- argument parsing / result building ----------------------------------
 * Format letters: 'i' int*, 'l' long*, 'd' double*, 's' const char**,
 * 's#' const char** + Py_ssize_t* (pointer+length), 'y'/'y#' like 's'/'s#'
 * but for a PYOBJ_BYTES item instead of PYOBJ_STR, 'O' PyObject** (raw,
 * borrowed, no conversion). Py_BuildValue mirrors the same letters, reading
 * values instead of writing through pointers ('s'/'y' and their '#' forms
 * both just take a const char* — '#' additionally consumes a Py_ssize_t
 * length). Any other letter fails loudly (returns 0 / NULL), same M1
 * policy. */
int PyArg_ParseTuple(PyObject *args, const char *format, ...);
PyObject *Py_BuildValue(const char *format, ...);

/* --- errors ---------------------------------------------------------------
 * A single pending-error slot (pxx has no threads to race it). `type` is
 * carried through unmodified — pxx's own runtime bridge (the NilPy import
 * host) is what turns the stored message into a raised NilPy exception, so
 * the extension-visible object identity of `type` is never inspected here. */
extern PyObject *PyExc_Exception;
extern PyObject *PyExc_ValueError;
extern PyObject *PyExc_TypeError;
extern PyObject *PyExc_RuntimeError;
/* M5a: the rest of the set generated (Cython) code names unconditionally in
 * its error and deprecation paths. Same treatment as the four above — an
 * identity, not a class hierarchy: nothing here inspects them beyond `==`. */
extern PyObject *PyExc_AttributeError;
extern PyObject *PyExc_ImportError;
extern PyObject *PyExc_OverflowError;
extern PyObject *PyExc_DeprecationWarning;
extern PyObject *PyExc_RuntimeWarning;
extern PyObject *PyExc_SystemError;
extern PyObject *PyExc_MemoryError;
extern PyObject *PyExc_StopIteration;

void PyErr_SetString(PyObject *type, const char *message);
PyObject *PyErr_Occurred(void);
void PyErr_Clear(void);
/* pxx-internal: lets the embedding driver read the pending message without
   exposing PyObject internals; not part of the real CPython API. */
const char *__pxx_PyErr_Message(void);
/* pxx-internal: stops the program naming a C-API function this runtime does
   not implement. Used only by the entries listed at the end of this header —
   see the note there for why they exist at all. */
void __pxx_cpyext_unsupported(const char *name);

/* --- module definition ---------------------------------------------------- */
typedef PyObject *(*PyCFunction)(PyObject *self, PyObject *args);

#define METH_VARARGS 0x0001
#define METH_KEYWORDS 0x0002 /* ml_meth is really PyCFunctionWithKeywords */
#define METH_O       0x0008  /* ml_meth called as fn(self, theSingleArg) directly */

#define METH_NOARGS  0x0004
#define METH_FASTCALL 0x0080  /* args as a C array, not a tuple */

/* METH_KEYWORDS and METH_FASTCALL entries carry a wider function through the
 * same one-field ml_meth slot, exactly as CPython does — the cast IS the API,
 * and ml_flags is what says which signature is really there. */
typedef PyObject *(*PyCFunctionWithKeywords)(PyObject *self, PyObject *args,
                                             PyObject *kwargs);
typedef PyObject *(*PyCFunctionFast)(PyObject *self, PyObject *const *args,
                                     Py_ssize_t nargs);
typedef PyObject *(*PyCFunctionFastWithKeywords)(PyObject *self,
                                                 PyObject *const *args,
                                                 Py_ssize_t nargs,
                                                 PyObject *kwnames);
/* The pre-3.13 private spellings. CPython renamed these without removing the
 * old names, and generated code picks whichever the CLAIMED version had — so
 * both must exist here or a cast lands on an undeclared name. */
typedef PyCFunctionFast _PyCFunctionFast;
typedef PyCFunctionFastWithKeywords _PyCFunctionFastWithKeywords;

typedef struct PyMethodDef {
    const char  *ml_name;
    PyCFunction  ml_meth;
    int          ml_flags;
    const char  *ml_doc;
} PyMethodDef;

typedef struct PyModuleDef_Base {
    long m_reserved;
} PyModuleDef_Base;

#define PyModuleDef_HEAD_INIT { 0 }

/* M4: multi-phase init's slot table (PyModuleDef_Slot). This runtime only
 * ever collapses multi-phase init to single-phase (see PyModuleDef_Init
 * below), so slot VALUES are never interpreted — the field exists purely so
 * a `.m_slots = ...` designated initializer in vendored source compiles. */
typedef struct PyModuleDef_Slot {
    int   slot;
    void *value;
} PyModuleDef_Slot;

/* The PEP 489 slot IDs. Named because generated code builds the table with
 * them; the values are never interpreted here (PyModuleDef_Init collapses
 * multi-phase init to single-phase — see below), and a real Py_mod_exec slot
 * is NOT executed. An extension that needs one is out of scope today, and
 * silently not running it would be exactly the failure mode this header
 * refuses; that gap is recorded on the cpyext ticket, not papered over. */
#define Py_mod_create 1
#define Py_mod_exec   2

typedef struct PyModuleDef {
    PyModuleDef_Base  m_base;
    const char       *m_name;
    const char       *m_doc;
    Py_ssize_t        m_size;
    PyMethodDef      *m_methods;
    PyModuleDef_Slot *m_slots;
} PyModuleDef;

PyObject *PyModule_Create2(PyModuleDef *def, int module_api_version);
#define PyModule_Create(def) PyModule_Create2((def), 1013)

/* Real CPython's multi-phase init (PEP 489) returns the PyModuleDef* itself
 * from PyInit_<name>, and the import machinery later executes any
 * Py_mod_exec slot to build the actual module. This runtime has no import
 * machinery to hand that off to, and pxx's own embedding driver (whatever
 * calls PyInit_<name>) wants a usable module object back immediately — so
 * PyModuleDef_Init collapses straight to single-phase (PyModule_Create2).
 * Honest for any extension whose slots are capability announcements only
 * (no Py_mod_exec, e.g. MarkupSafe's Py_mod_gil/Py_mod_multiple_interpreters)
 * — a real Py_mod_exec slot would need more work, not attempted here. */
PyObject *PyModuleDef_Init(PyModuleDef *def);

#define PyMODINIT_FUNC PyObject *

/* --- M5a: the surface a Cython-generated module names ----------------------
 *
 * Measured, not guessed: this is exactly the set of functions the smallest
 * possible Cython 3.2 module references when generated with `-X binding=False`
 * and compiled with `-DPy_LIMITED_API` (see the M5 scoping section on
 * feature-nilpy-cpyext-c-api-from-source for how the list was taken and why
 * those two knobs are the right target).
 *
 * DECLARED here, implemented in pyruntime.c only where this runtime can mean
 * it. The rest are declared so the translation unit COMPILES — generated code
 * emits utility functions it never calls — and left to fail at LINK with their
 * own name if something does reach them. That is the header's standing rule
 * and it is why nothing below is stubbed to return a plausible value.
 */

/* type / identity predicates */
int PyLong_Check(PyObject *o);
int PyLong_CheckExact(PyObject *o);
int PyUnicode_CheckExact(PyObject *o);
int PyBytes_CheckExact(PyObject *o);
int PyTuple_Check(PyObject *o);
int PyByteArray_Check(PyObject *o);
int PyCFunction_Check(PyObject *o);

/* long: the widths beyond M1's plain `long` */
PyObject *PyLong_FromLongLong(long long v);
PyObject *PyLong_FromUnsignedLong(unsigned long v);
PyObject *PyLong_FromUnsignedLongLong(unsigned long long v);
PyObject *PyLong_FromSize_t(size_t v);
long long PyLong_AsLongLong(PyObject *o);
unsigned long PyLong_AsUnsignedLong(PyObject *o);
unsigned long long PyLong_AsUnsignedLongLong(PyObject *o);
Py_ssize_t PyLong_AsSsize_t(PyObject *o);

/* number protocol — the operators Cython's int conversion helpers use */
PyObject *PyNumber_Long(PyObject *o);
PyObject *PyNumber_Index(PyObject *o);
PyObject *PyNumber_And(PyObject *a, PyObject *b);
PyObject *PyNumber_Rshift(PyObject *a, PyObject *b);
PyObject *PyNumber_Invert(PyObject *o);

/* object protocol */
int PyObject_IsTrue(PyObject *o);
Py_hash_t PyObject_Hash(PyObject *o);
int PyObject_RichCompareBool(PyObject *a, PyObject *b, int op);
PyObject *PyObject_GetAttr(PyObject *o, PyObject *name);
PyObject *PyObject_GetAttrString(PyObject *o, const char *name);
int PyObject_SetAttr(PyObject *o, PyObject *name, PyObject *v);
int PyObject_SetAttrString(PyObject *o, const char *name, PyObject *v);
PyObject *PyObject_Call(PyObject *callable, PyObject *args, PyObject *kwargs);
PyObject *PyObject_CallFunctionObjArgs(PyObject *callable, ...);
/* PyErr_Format / PyErr_WarnFormat's shared formatter: printf plus CPython's
   object specifiers %U %S %R %A. Exposed so both can share one implementation. */
void __pxx_cpyext_vformat(char *buf, size_t cap, const char *format, va_list ap);
/* Py_BuildValue's format language over a va_list — the single parser both
   Py_BuildValue and PyObject_CallFunction go through. */
PyObject *__pxx_cpyext_vbuildvalue(const char *format, va_list ap);

/* unicode / bytes / bytearray */
Py_ssize_t PyTuple_Size(PyObject *t);
int PyBytes_AsStringAndSize(PyObject *o, char **buf, Py_ssize_t *len);
PyObject *PyByteArray_FromStringAndSize(const char *s, Py_ssize_t n);
char *PyByteArray_AsString(PyObject *o);
Py_ssize_t PyByteArray_Size(PyObject *o);
int PyUnicode_Compare(PyObject *a, PyObject *b);
int PyUnicode_CompareWithASCIIString(PyObject *a, const char *s);
PyObject *PyUnicode_Decode(const char *s, Py_ssize_t size,
                           const char *encoding, const char *errors);
PyObject *PyUnicode_DecodeUTF8(const char *s, Py_ssize_t size,
                               const char *errors);
PyObject *PyUnicode_FromFormat(const char *format, ...);
void PyUnicode_InternInPlace(PyObject **p);

/* dict */
int PyDict_Contains(PyObject *d, PyObject *key);
PyObject *PyDict_GetItemString(PyObject *d, const char *key);   /* borrowed */
PyObject *PyDict_GetItemWithError(PyObject *d, PyObject *key);  /* borrowed */
int PyDict_SetItemString(PyObject *d, const char *key, PyObject *v);
int PyDict_Update(PyObject *a, PyObject *b);

/* errors */
int PyErr_ExceptionMatches(PyObject *exc);
int PyErr_GivenExceptionMatches(PyObject *given, PyObject *exc);
void PyErr_Fetch(PyObject **ptype, PyObject **pvalue, PyObject **ptraceback);
void PyErr_Restore(PyObject *type, PyObject *value, PyObject *traceback);
PyObject *PyErr_Format(PyObject *exc, const char *format, ...);
int PyErr_WarnEx(PyObject *category, const char *message, Py_ssize_t stacklevel);
int PyErr_WarnFormat(PyObject *category, Py_ssize_t stacklevel,
                     const char *format, ...);

/* raw memory (extension-owned buffers, never a NilPy object) */
void *PyMem_Malloc(size_t n);
void *PyMem_Realloc(void *p, size_t n);
void PyMem_Free(void *p);

/* argument-parsing helper generated keyword code calls before parsing */
int PyArg_ValidateKeywordArguments(PyObject *kwargs);

/* module / import / sys. There is no import machinery in this runtime (a pxx
 * program's modules are linked in), so these exist for the shapes generated
 * code emits around module setup; anything that genuinely needs a live import
 * system is out of scope and is meant to fail loudly. */
PyObject *PyModule_GetDict(PyObject *m);                        /* borrowed */
PyObject *PyModule_NewObject(PyObject *name);
PyObject *PyImport_AddModule(const char *name);                 /* borrowed */
PyObject *PyImport_GetModuleDict(void);                         /* borrowed */
PyObject *PyImport_ImportModule(const char *name);
PyObject *PySys_GetObject(const char *name);                    /* borrowed */

/* formatting */
int PyOS_snprintf(char *str, size_t size, const char *format, ...);

/* --- M5b leaf surface -----------------------------------------------------
 * The mechanical remainder of what a `binding=True` Cython module names: ways
 * to call, to ask, and to slice, none of which need a decision. */
int PyCallable_Check(PyObject *o);
int PyDict_Check(PyObject *o);
int PyDict_CheckExact(PyObject *o);
PyObject *PyErr_NoMemory(void);
PyObject *PyObject_CallObject(PyObject *callable, PyObject *args);
PyObject *PyObject_CallFunction(PyObject *callable, const char *format, ...);
PyObject *PyObject_CallMethodObjArgs(PyObject *o, PyObject *name, ...);
int PyObject_HasAttr(PyObject *o, PyObject *name);
int PyObject_HasAttrString(PyObject *o, const char *name);
PyObject *PySequence_GetItem(PyObject *o, Py_ssize_t i);
PyObject *PyTuple_Pack(Py_ssize_t n, ...);
PyObject *PyTuple_GetSlice(PyObject *t, Py_ssize_t lo, Py_ssize_t hi);
int PyCFunction_GetFlags(PyObject *op);
PyObject *PyCFunction_GetSelf(PyObject *op);              /* borrowed */
/* There is no importer, so this cannot import; it is declared because Cython's
 * `__Pyx_Import` names it, and it reports ImportError rather than inventing a
 * module — same rule as PyImport_ImportModule. */
PyObject *PyImport_ImportModuleLevelObject(PyObject *name, PyObject *globals,
                                           PyObject *locals, PyObject *fromlist,
                                           int level);

/* --- declared but deliberately NOT implemented ----------------------------
 * Each is referenced from Cython utility code that a compiled-ahead-of-time
 * extension does not execute. They are declared so the module compiles, and
 * NOT defined so that anything actually calling one fails at link naming it.
 * Do not stub these: a stub that returns NULL or 0 turns "unsupported" into a
 * wrong answer, which is the failure mode this whole header refuses.
 *
 *   Py_CompileString / PyEval_EvalCode  — no Python compiler here
 *   PyTraceBack_Here                    — no PyFrameObject to record
 *   PyInterpreterState_Get / _GetID     — single, implicit interpreter
 *   PyMemoryView_FromMemory             — buffer protocol is M6
 *
 * Four names left this list at M5b and are now real: PyType_GetQualName (heap
 * types exist), PyObject_Vectorcall (the protocol is honoured through
 * tp_vectorcall_offset), and PyCFunction_New/_NewEx/_GetFunction (builtin
 * function objects landed at M5a). PyObject_VectorcallMethod stays a stop —
 * it needs attribute lookup that yields an unbound callable plus the
 * arguments-offset convention, and nothing generated has reached it.
 */
struct _object *Py_CompileString(const char *str, const char *filename, int start);
PyObject *PyEval_EvalCode(PyObject *co, PyObject *globals, PyObject *locals);
int PyTraceBack_Here(void *frame);
void *PyInterpreterState_Get(void);
long long PyInterpreterState_GetID(void *interp);
PyObject *PyType_GetQualName(PyTypeObject *t);
PyObject *PyObject_Vectorcall(PyObject *callable, PyObject *const *args,
                              size_t nargsf, PyObject *kwnames);
PyObject *PyObject_VectorcallMethod(PyObject *name, PyObject *const *args,
                                    size_t nargsf, PyObject *kwnames);
Py_ssize_t PyVectorcall_NARGS(size_t nargsf);
PyObject *PyCFunction_New(PyMethodDef *ml, PyObject *self);
PyObject *PyCFunction_NewEx(PyMethodDef *ml, PyObject *self, PyObject *module);
PyCFunction PyCFunction_GetFunction(PyObject *op);
PyObject *PyMemoryView_FromMemory(char *mem, Py_ssize_t size, int flags);
#define PyBUF_READ  0x100
#define PyBUF_WRITE 0x200

#endif /* PXX_CPYEXT_PYTHON_H */
