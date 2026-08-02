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

typedef struct _object {
    long   ob_refcnt;
    int    ob_kind;   /* PYOBJ_* above */
    long   ob_ival;   /* PYOBJ_LONG payload */
    double ob_fval;   /* PYOBJ_FLOAT payload */
    void  *ob_ptr;    /* PYOBJ_TUPLE/PYOBJ_LIST: PyObject** items;
                          PYOBJ_MODULE: PyMethodDef*;
                          PYOBJ_STR/PYOBJ_BYTES: char* bytes (NUL-terminated);
                          PYOBJ_DICT: PyDictEntry* pairs */
    long   ob_size;   /* PYOBJ_TUPLE/PYOBJ_LIST: item count;
                          PYOBJ_MODULE: method count;
                          PYOBJ_STR/PYOBJ_BYTES: byte length (excl. the NUL);
                          PYOBJ_DICT: pair count */
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
#define Py_XDECREF(o) do { if ((o) != 0) Py_DecRef((PyObject *)(o)); } while (0)

/* A stub type object: part of the real API's shape, unused by M1's own
 * extension but declared so a `PyTypeObject *` field/parameter compiles. */
typedef struct _typeobject {
    const char *tp_name;
} PyTypeObject;

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

void PyErr_SetString(PyObject *type, const char *message);
PyObject *PyErr_Occurred(void);
void PyErr_Clear(void);
/* pxx-internal: lets the embedding driver read the pending message without
   exposing PyObject internals; not part of the real CPython API. */
const char *__pxx_PyErr_Message(void);

/* --- module definition ---------------------------------------------------- */
typedef PyObject *(*PyCFunction)(PyObject *self, PyObject *args);

#define METH_VARARGS 0x0001
#define METH_O       0x0008  /* ml_meth called as fn(self, theSingleArg) directly */

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

#endif /* PXX_CPYEXT_PYTHON_H */
