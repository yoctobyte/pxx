/* SPDX-License-Identifier: Zlib */
/* Implementation behind lib/cpyext/include/Python.h — see that file and
 * lib/cpyext/README.md. A tiny tagged-object model (long / float / string /
 * tuple / module / none) with refcounting.
 *
 * M1 "hello-ext": alloc/refcount, PyLong_*, PyTuple_*, PyArg_ParseTuple "i",
 * PyModule_Create2.
 * M2 "arguments and errors": PyFloat_*, PyUnicode_*, PyArg_ParseTuple /
 * Py_BuildValue widened to "i l d s s# O", and a pending-error slot behind
 * PyErr_SetString/PyErr_Occurred/PyErr_Clear.
 * M3 "strings and containers": PyBytes_* (str-distinct type), PyList_*,
 * PyDict_* (+ PyDict_Next iteration), and 'y'/'y#' bytes format letters. */

#include <Python.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>   /* M5a: warnings + the unsupported-API stop go to stderr */

PyObject _Py_NoneStruct = { 1, PYOBJ_NONE, 0, 0.0, 0, 0 };

/* Exception "type" singletons. Never allocated/freed through py_alloc/
 * Py_DecRef — like Py_None, they are process-global and their identity is
 * carried through PyErr_SetString unmodified. pxx's own embedding driver
 * only ever reads the stored MESSAGE (__pxx_PyErr_Message), never the type,
 * so these exist only so extension source that names them compiles/links. */
static PyObject g_exc_exception     = { 1, PYOBJ_NONE, 0, 0.0, 0, 0 };
static PyObject g_exc_valueerror    = { 1, PYOBJ_NONE, 0, 0.0, 0, 0 };
static PyObject g_exc_typeerror     = { 1, PYOBJ_NONE, 0, 0.0, 0, 0 };
static PyObject g_exc_runtimeerror  = { 1, PYOBJ_NONE, 0, 0.0, 0, 0 };

PyObject *PyExc_Exception    = &g_exc_exception;
PyObject *PyExc_ValueError   = &g_exc_valueerror;
PyObject *PyExc_TypeError    = &g_exc_typeerror;
PyObject *PyExc_RuntimeError = &g_exc_runtimeerror;

/* M5a adds six more exception singletons and the True/False objects, all with
   the same lifetime rule, so the "never free this" test became a list that
   would go stale silently the next time one is added. It is now an ADDRESS
   RANGE test instead: every static PyObject in this file lives between these
   two markers, so a new one is covered by declaring it there and nothing
   else. Declaring one outside the range is the only way to get it wrong, and
   that is visible at the declaration.

   The markers are ordinary objects rather than empty structs because a C
   object needs storage to have a distinct address at all. */
static PyObject g_static_lo = { 1, PYOBJ_NONE, 0, 0.0, 0, 0 };
static PyObject g_exc_attributeerror    = { 1, PYOBJ_NONE, 0, 0.0, 0, 0 };
static PyObject g_exc_importerror       = { 1, PYOBJ_NONE, 0, 0.0, 0, 0 };
static PyObject g_exc_overflowerror     = { 1, PYOBJ_NONE, 0, 0.0, 0, 0 };
static PyObject g_exc_deprecationwarn   = { 1, PYOBJ_NONE, 0, 0.0, 0, 0 };
static PyObject g_exc_runtimewarn       = { 1, PYOBJ_NONE, 0, 0.0, 0, 0 };
static PyObject g_exc_systemerror       = { 1, PYOBJ_NONE, 0, 0.0, 0, 0 };
/* True/False: the long objects 1 and 0 — this runtime has no bool kind, and
   the header says so rather than implying more. */
PyObject _Py_TrueStruct  = { 1, PYOBJ_LONG, 1, 0.0, 0, 0 };
PyObject _Py_FalseStruct = { 1, PYOBJ_LONG, 0, 0.0, 0, 0 };
static PyObject g_static_hi = { 1, PYOBJ_NONE, 0, 0.0, 0, 0 };

PyObject *PyExc_AttributeError     = &g_exc_attributeerror;
PyObject *PyExc_ImportError        = &g_exc_importerror;
PyObject *PyExc_OverflowError      = &g_exc_overflowerror;
PyObject *PyExc_DeprecationWarning = &g_exc_deprecationwarn;
PyObject *PyExc_RuntimeWarning     = &g_exc_runtimewarn;
PyObject *PyExc_SystemError        = &g_exc_systemerror;

/* Process-global objects are never allocated by py_alloc and must never be
   freed by Py_DecRef. Py_None predates the range and is checked separately. */
static int py_is_static(PyObject *o) {
    if (o == &g_exc_exception || o == &g_exc_valueerror ||
        o == &g_exc_typeerror || o == &g_exc_runtimeerror) return 1;
    return o >= &g_static_lo && o <= &g_static_hi;
}

static PyObject *g_err_type = 0;
static char g_err_msg[512];

static PyObject *py_alloc(int kind) {
    PyObject *o;
    o = (PyObject *)malloc(sizeof(PyObject));
    o->ob_refcnt = 1;
    o->ob_kind = kind;
    o->ob_ival = 0;
    o->ob_fval = 0.0;
    o->ob_ptr = 0;
    o->ob_size = 0;
    o->ob_attrs = 0;
    return o;
}

void Py_IncRef(PyObject *o) {
    if (o == 0) return;
    o->ob_refcnt = o->ob_refcnt + 1;
}

void Py_DecRef(PyObject *o) {
    if (o == 0) return;
    if (o == &_Py_NoneStruct) return;
    if (py_is_static(o)) return;
    o->ob_refcnt = o->ob_refcnt - 1;
    if (o->ob_refcnt <= 0) {
        if ((o->ob_kind == PYOBJ_TUPLE || o->ob_kind == PYOBJ_STR ||
             o->ob_kind == PYOBJ_BYTES || o->ob_kind == PYOBJ_LIST ||
             o->ob_kind == PYOBJ_DICT) && o->ob_ptr != 0)
            free(o->ob_ptr);
        /* PYOBJ_CFUNC's ob_ptr is a PyMethodDef the extension OWNS (a static
           table); PYOBJ_MODULE's likewise. Neither is freed here — only the
           attribute dict this object allocated for itself. */
        if (o->ob_attrs != 0) Py_DecRef(o->ob_attrs);
        free(o);
    }
}

PyObject *PyLong_FromLong(long v) {
    PyObject *o;
    o = py_alloc(PYOBJ_LONG);
    o->ob_ival = v;
    return o;
}

long PyLong_AsLong(PyObject *o) {
    if (o == 0) return -1;
    if (o->ob_kind == PYOBJ_FLOAT) return (long)o->ob_fval;
    return o->ob_ival;
}

PyObject *PyFloat_FromDouble(double v) {
    PyObject *o;
    o = py_alloc(PYOBJ_FLOAT);
    o->ob_fval = v;
    return o;
}

double PyFloat_AsDouble(PyObject *o) {
    if (o == 0) return -1.0;
    if (o->ob_kind == PYOBJ_LONG) return (double)o->ob_ival;
    return o->ob_fval;
}

PyObject *PyUnicode_FromStringAndSize(const char *s, Py_ssize_t n) {
    PyObject *o;
    char *buf;
    Py_ssize_t i;
    o = py_alloc(PYOBJ_STR);
    buf = (char *)malloc((size_t)(n + 1));
    for (i = 0; i < n; i++) buf[i] = s[i];
    buf[n] = 0;
    o->ob_ptr = (void *)buf;
    o->ob_size = n;
    return o;
}

PyObject *PyUnicode_FromString(const char *s) {
    Py_ssize_t n;
    n = 0;
    while (s[n] != 0) n = n + 1;
    return PyUnicode_FromStringAndSize(s, n);
}

const char *PyUnicode_AsUTF8(PyObject *o) {
    if (o == 0 || o->ob_kind != PYOBJ_STR) return 0;
    return (const char *)o->ob_ptr;
}

int PyUnicode_Check(PyObject *o) {
    return o != 0 && o->ob_kind == PYOBJ_STR;
}

int PyUnicode_READY(PyObject *o) {
    (void)o;
    return 0;
}

int PyUnicode_KIND(PyObject *o) {
    (void)o;
    return PyUnicode_1BYTE_KIND;
}

Py_UCS1 *PyUnicode_1BYTE_DATA(PyObject *o) {
    return (Py_UCS1 *)o->ob_ptr;
}

Py_UCS2 *PyUnicode_2BYTE_DATA(PyObject *o) {
    return (Py_UCS2 *)o->ob_ptr; /* dead code on this runtime: KIND never says 2BYTE */
}

Py_UCS4 *PyUnicode_4BYTE_DATA(PyObject *o) {
    return (Py_UCS4 *)o->ob_ptr; /* dead code on this runtime: KIND never says 4BYTE */
}

Py_ssize_t PyUnicode_GET_LENGTH(PyObject *o) {
    return o->ob_size;
}

int PyUnicode_IS_ASCII(PyObject *o) {
    (void)o;
    return 1;
}

PyObject *PyUnicode_New(Py_ssize_t size, Py_UCS4 maxchar) {
    PyObject *o;
    char *buf;
    (void)maxchar; /* always byte-width on this runtime */
    o = py_alloc(PYOBJ_STR);
    buf = (char *)malloc((size_t)(size + 1));
    buf[size] = 0;
    o->ob_ptr = (void *)buf;
    o->ob_size = size;
    return o;
}

PyObject *PyBytes_FromStringAndSize(const char *s, Py_ssize_t n) {
    PyObject *o;
    char *buf;
    Py_ssize_t i;
    o = py_alloc(PYOBJ_BYTES);
    buf = (char *)malloc((size_t)(n + 1));
    for (i = 0; i < n; i++) buf[i] = s[i];
    buf[n] = 0;
    o->ob_ptr = (void *)buf;
    o->ob_size = n;
    return o;
}

char *PyBytes_AsString(PyObject *o) {
    if (o == 0 || o->ob_kind != PYOBJ_BYTES) return 0;
    return (char *)o->ob_ptr;
}

Py_ssize_t PyBytes_Size(PyObject *o) {
    if (o == 0 || o->ob_kind != PYOBJ_BYTES) return -1;
    return o->ob_size;
}

PyObject *PyTuple_New(Py_ssize_t n) {
    PyObject *o;
    PyObject **items;
    Py_ssize_t cap;
    Py_ssize_t i;
    o = py_alloc(PYOBJ_TUPLE);
    cap = (n > 0) ? n : 1;
    items = (PyObject **)malloc(sizeof(PyObject *) * (size_t)cap);
    for (i = 0; i < n; i++) items[i] = 0;
    o->ob_ptr = (void *)items;
    o->ob_size = n;
    return o;
}

int PyTuple_SetItem(PyObject *t, Py_ssize_t i, PyObject *v) {
    PyObject **items;
    if (t == 0 || t->ob_kind != PYOBJ_TUPLE) return -1;
    if (i < 0 || i >= t->ob_size) return -1;
    items = (PyObject **)t->ob_ptr;
    items[i] = v;
    return 0;
}

PyObject *PyTuple_GetItem(PyObject *t, Py_ssize_t i) {
    PyObject **items;
    if (t == 0 || t->ob_kind != PYOBJ_TUPLE) return 0;
    if (i < 0 || i >= t->ob_size) return 0;
    items = (PyObject **)t->ob_ptr;
    return items[i];
}

PyObject *PyList_New(Py_ssize_t n) {
    PyObject *o;
    PyObject **items;
    Py_ssize_t cap;
    Py_ssize_t i;
    o = py_alloc(PYOBJ_LIST);
    cap = (n > 0) ? n : 1;
    items = (PyObject **)malloc(sizeof(PyObject *) * (size_t)cap);
    for (i = 0; i < n; i++) items[i] = 0;
    o->ob_ptr = (void *)items;
    o->ob_size = n;
    return o;
}

int PyList_SetItem(PyObject *l, Py_ssize_t i, PyObject *v) {
    PyObject **items;
    if (l == 0 || l->ob_kind != PYOBJ_LIST) return -1;
    if (i < 0 || i >= l->ob_size) return -1;
    items = (PyObject **)l->ob_ptr;
    items[i] = v;
    return 0;
}

PyObject *PyList_GetItem(PyObject *l, Py_ssize_t i) {
    PyObject **items;
    if (l == 0 || l->ob_kind != PYOBJ_LIST) return 0;
    if (i < 0 || i >= l->ob_size) return 0;
    items = (PyObject **)l->ob_ptr;
    return items[i];
}

int PyList_Append(PyObject *l, PyObject *v) {
    PyObject **items;
    if (l == 0 || l->ob_kind != PYOBJ_LIST) return -1;
    items = (PyObject **)realloc(l->ob_ptr, sizeof(PyObject *) * (size_t)(l->ob_size + 1));
    items[l->ob_size] = v;
    Py_IncRef(v);
    l->ob_ptr = (void *)items;
    l->ob_size = l->ob_size + 1;
    return 0;
}

Py_ssize_t PyList_Size(PyObject *l) {
    if (l == 0 || l->ob_kind != PYOBJ_LIST) return -1;
    return l->ob_size;
}

static int py_obj_eq(PyObject *a, PyObject *b) {
    if (a == b) return 1;
    if (a == 0 || b == 0) return 0;
    if (a->ob_kind != b->ob_kind) return 0;
    if (a->ob_kind == PYOBJ_LONG) return a->ob_ival == b->ob_ival;
    if (a->ob_kind == PYOBJ_STR || a->ob_kind == PYOBJ_BYTES)
        return strcmp((char *)a->ob_ptr, (char *)b->ob_ptr) == 0;
    return 0;
}

PyObject *PyDict_New(void) {
    return py_alloc(PYOBJ_DICT);
}

int PyDict_SetItem(PyObject *d, PyObject *key, PyObject *value) {
    PyDictEntry *pairs;
    long i;
    if (d == 0 || d->ob_kind != PYOBJ_DICT) return -1;
    pairs = (PyDictEntry *)d->ob_ptr;
    for (i = 0; i < d->ob_size; i++) {
        if (py_obj_eq(pairs[i].key, key)) {
            Py_IncRef(value);
            Py_DecRef(pairs[i].value);
            pairs[i].value = value;
            return 0;
        }
    }
    pairs = (PyDictEntry *)realloc(d->ob_ptr, sizeof(PyDictEntry) * (size_t)(d->ob_size + 1));
    Py_IncRef(key);
    Py_IncRef(value);
    pairs[d->ob_size].key = key;
    pairs[d->ob_size].value = value;
    d->ob_ptr = (void *)pairs;
    d->ob_size = d->ob_size + 1;
    return 0;
}

PyObject *PyDict_GetItem(PyObject *d, PyObject *key) {
    PyDictEntry *pairs;
    long i;
    if (d == 0 || d->ob_kind != PYOBJ_DICT) return 0;
    pairs = (PyDictEntry *)d->ob_ptr;
    for (i = 0; i < d->ob_size; i++) {
        if (py_obj_eq(pairs[i].key, key)) return pairs[i].value;
    }
    return 0;
}

Py_ssize_t PyDict_Size(PyObject *d) {
    if (d == 0 || d->ob_kind != PYOBJ_DICT) return -1;
    return d->ob_size;
}

int PyDict_Next(PyObject *d, Py_ssize_t *ppos, PyObject **pkey, PyObject **pvalue) {
    PyDictEntry *pairs;
    if (d == 0 || d->ob_kind != PYOBJ_DICT) return 0;
    if (*ppos < 0 || *ppos >= d->ob_size) return 0;
    pairs = (PyDictEntry *)d->ob_ptr;
    if (pkey != 0) *pkey = pairs[*ppos].key;
    if (pvalue != 0) *pvalue = pairs[*ppos].value;
    *ppos = *ppos + 1;
    return 1;
}

int PyArg_ParseTuple(PyObject *args, const char *format, ...) {
    va_list ap;
    int fi, argIdx, ok;
    char c;
    PyObject *item;
    int *idst;
    long *ldst;
    double *ddst;
    const char **sdst;
    Py_ssize_t *lendst;
    PyObject **odst;

    fi = 0;
    argIdx = 0;
    ok = 1;
    va_start(ap, format);
    while (format[fi] != 0 && ok) {
        c = format[fi];
        item = PyTuple_GetItem(args, argIdx);
        if (c == 'i') {
            idst = va_arg(ap, int *);
            if (item == 0 || item->ob_kind != PYOBJ_LONG) ok = 0;
            else *idst = (int)item->ob_ival;
            argIdx = argIdx + 1;
        } else if (c == 'l') {
            ldst = va_arg(ap, long *);
            if (item == 0 || item->ob_kind != PYOBJ_LONG) ok = 0;
            else *ldst = item->ob_ival;
            argIdx = argIdx + 1;
        } else if (c == 'd') {
            ddst = va_arg(ap, double *);
            if (item == 0) {
                ok = 0;
            } else if (item->ob_kind == PYOBJ_FLOAT) {
                *ddst = item->ob_fval;
            } else if (item->ob_kind == PYOBJ_LONG) {
                *ddst = (double)item->ob_ival;
            } else {
                ok = 0;
            }
            argIdx = argIdx + 1;
        } else if (c == 's' || c == 'y') {
            sdst = va_arg(ap, const char **);
            if (item == 0 || item->ob_kind != ((c == 's') ? PYOBJ_STR : PYOBJ_BYTES)) {
                ok = 0;
            } else {
                *sdst = (const char *)item->ob_ptr;
            }
            if (format[fi + 1] == '#') {
                lendst = va_arg(ap, Py_ssize_t *);
                if (ok) *lendst = item->ob_size;
                fi = fi + 1;
            }
            argIdx = argIdx + 1;
        } else if (c == 'O') {
            odst = va_arg(ap, PyObject **);
            if (item == 0) ok = 0;
            else *odst = item;
            argIdx = argIdx + 1;
        } else {
            ok = 0;
        }
        fi = fi + 1;
    }
    va_end(ap);
    if (!ok) PyErr_SetString(PyExc_TypeError, "PyArg_ParseTuple: argument type/count mismatch");
    return ok;
}

PyObject *Py_BuildValue(const char *format, ...) {
    va_list ap;
    int fi, n, i;
    char c;
    PyObject *items[8];
    PyObject *tup;
    int ival;
    long lval;
    double dval;
    const char *sval;
    Py_ssize_t slen;
    PyObject *oval;

    fi = 0;
    n = 0;
    va_start(ap, format);
    while (format[fi] != 0 && n < 8) {
        c = format[fi];
        if (c == 'i') {
            ival = va_arg(ap, int);
            items[n] = PyLong_FromLong((long)ival);
            n = n + 1;
        } else if (c == 'l') {
            lval = va_arg(ap, long);
            items[n] = PyLong_FromLong(lval);
            n = n + 1;
        } else if (c == 'd') {
            dval = va_arg(ap, double);
            items[n] = PyFloat_FromDouble(dval);
            n = n + 1;
        } else if (c == 's' || c == 'y') {
            sval = va_arg(ap, const char *);
            if (format[fi + 1] == '#') {
                slen = va_arg(ap, Py_ssize_t);
                items[n] = (c == 's') ? PyUnicode_FromStringAndSize(sval, slen)
                                      : PyBytes_FromStringAndSize(sval, slen);
                fi = fi + 1;
            } else if (c == 's') {
                items[n] = PyUnicode_FromString(sval);
            } else {
                Py_ssize_t blen;
                blen = 0;
                while (sval[blen] != 0) blen = blen + 1;
                items[n] = PyBytes_FromStringAndSize(sval, blen);
            }
            n = n + 1;
        } else if (c == 'O') {
            oval = va_arg(ap, PyObject *);
            Py_IncRef(oval);
            items[n] = oval;
            n = n + 1;
        } else {
            va_end(ap);
            return 0;
        }
        fi = fi + 1;
    }
    va_end(ap);
    if (n == 0) return Py_None;
    if (n == 1) return items[0];
    tup = PyTuple_New(n);
    for (i = 0; i < n; i++) PyTuple_SetItem(tup, i, items[i]);
    return tup;
}

void PyErr_SetString(PyObject *type, const char *message) {
    int i;
    g_err_type = type;
    i = 0;
    while (message[i] != 0 && i < 511) { g_err_msg[i] = message[i]; i = i + 1; }
    g_err_msg[i] = 0;
}

PyObject *PyErr_Occurred(void) {
    return g_err_type;
}

void PyErr_Clear(void) {
    g_err_type = 0;
    g_err_msg[0] = 0;
}

const char *__pxx_PyErr_Message(void) {
    return g_err_msg;
}

PyObject *PyModule_Create2(PyModuleDef *def, int module_api_version) {
    PyObject *o;
    long count;
    (void)module_api_version;
    o = py_alloc(PYOBJ_MODULE);
    o->ob_ptr = (void *)def->m_methods;
    count = 0;
    if (def->m_methods != 0)
        while (def->m_methods[count].ml_name != 0) count = count + 1;
    o->ob_size = count;
    return o;
}

/* ==========================================================================
 * M5a: the surface a Cython-generated module needs.
 *
 * Measured, not guessed — see the M5 scoping section on
 * feature-nilpy-cpyext-c-api-from-source. Everything here is referenced by the
 * smallest Cython 3.2 module built with `-X binding=False` and
 * `-DPy_LIMITED_API`; most of it is referenced from utility code the module
 * never executes, which is exactly why the two rules below matter more than
 * the implementations.
 *
 * RULE 1 — no plausible lies. Where this runtime genuinely cannot do the
 * thing, the function sets the error Python itself would set (an object with
 * no attributes really does raise AttributeError; a non-callable really does
 * raise TypeError) and returns the failure value. It never returns a made-up
 * success.
 *
 * RULE 2 — where not even an honest error exists, __pxx_cpyext_unsupported()
 * names the function on stderr and exits. Those entries are unreachable in a
 * compiled-ahead-of-time extension; if one is ever reached, the program stops
 * there rather than continuing on a fiction.
 * ========================================================================== */

void __pxx_cpyext_unsupported(const char *name) {
    fprintf(stderr, "pxx cpyext: unsupported C-API function: %s\n", name);
    fflush(stderr);
    exit(70);
}

/* --- type objects --------------------------------------------------------
   Identity only: `Py_TYPE(o) == &PyDict_Type` is the entire contract this
   runtime honours, and tp_name is for diagnostics. No slots hang off them —
   heap types with real slots are M5b. */
PyTypeObject PyLong_Type    = { "int" };
PyTypeObject PyFloat_Type   = { "float" };
PyTypeObject PyUnicode_Type = { "str" };
PyTypeObject PyBytes_Type   = { "bytes" };
PyTypeObject PyTuple_Type   = { "tuple" };
PyTypeObject PyList_Type    = { "list" };
PyTypeObject PyDict_Type    = { "dict" };
static PyTypeObject g_type_none   = { "NoneType" };
static PyTypeObject g_type_module = { "module" };

PyTypeObject *Py_TYPE(PyObject *o) {
    if (o == 0) return &g_type_none;
    if (o->ob_kind == PYOBJ_LONG)   return &PyLong_Type;
    if (o->ob_kind == PYOBJ_FLOAT)  return &PyFloat_Type;
    if (o->ob_kind == PYOBJ_STR)    return &PyUnicode_Type;
    if (o->ob_kind == PYOBJ_BYTES)  return &PyBytes_Type;
    if (o->ob_kind == PYOBJ_TUPLE)  return &PyTuple_Type;
    if (o->ob_kind == PYOBJ_LIST)   return &PyList_Type;
    if (o->ob_kind == PYOBJ_DICT)   return &PyDict_Type;
    if (o->ob_kind == PYOBJ_MODULE) return &g_type_module;
    return &g_type_none;
}

/* --- predicates ----------------------------------------------------------
   Exact and non-exact coincide here: there is no subclassing in this object
   model, so `CheckExact` and `Check` cannot disagree. Stated rather than left
   to look like an oversight. */
int PyLong_Check(PyObject *o)       { return o != 0 && o->ob_kind == PYOBJ_LONG; }
int PyLong_CheckExact(PyObject *o)  { return PyLong_Check(o); }
int PyUnicode_CheckExact(PyObject *o) { return PyUnicode_Check(o); }
int PyBytes_CheckExact(PyObject *o) { return o != 0 && o->ob_kind == PYOBJ_BYTES; }
int PyTuple_Check(PyObject *o)      { return o != 0 && o->ob_kind == PYOBJ_TUPLE; }
int PyByteArray_Check(PyObject *o)  { return o != 0 && o->ob_kind == PYOBJ_BYTES; }
int PyCFunction_Check(PyObject *o)  { return o != 0 && o->ob_kind == PYOBJ_CFUNC; }

/* --- long: the widths beyond plain `long` -------------------------------- */
PyObject *PyLong_FromLongLong(long long v)               { return PyLong_FromLong((long)v); }
PyObject *PyLong_FromUnsignedLong(unsigned long v)       { return PyLong_FromLong((long)v); }
PyObject *PyLong_FromUnsignedLongLong(unsigned long long v) { return PyLong_FromLong((long)v); }
PyObject *PyLong_FromSize_t(size_t v)                    { return PyLong_FromLong((long)v); }
long long PyLong_AsLongLong(PyObject *o)                 { return (long long)PyLong_AsLong(o); }
unsigned long PyLong_AsUnsignedLong(PyObject *o)         { return (unsigned long)PyLong_AsLong(o); }
unsigned long long PyLong_AsUnsignedLongLong(PyObject *o){ return (unsigned long long)PyLong_AsLong(o); }
Py_ssize_t PyLong_AsSsize_t(PyObject *o)                 { return (Py_ssize_t)PyLong_AsLong(o); }

/* --- number protocol ------------------------------------------------------
   Integers only. Anything else raises TypeError, which is what CPython does
   for a type with no nb_ slot — an honest refusal, not a wrong number. */
static int py_as_long(PyObject *o, long *out) {
    if (o == 0) return 0;
    if (o->ob_kind == PYOBJ_LONG)  { *out = o->ob_ival; return 1; }
    if (o->ob_kind == PYOBJ_FLOAT) { *out = (long)o->ob_fval; return 1; }
    return 0;
}

PyObject *PyNumber_Long(PyObject *o) {
    long v;
    if (!py_as_long(o, &v)) {
        PyErr_SetString(PyExc_TypeError, "int() argument must be a number");
        return 0;
    }
    return PyLong_FromLong(v);
}

PyObject *PyNumber_Index(PyObject *o) {
    if (!PyLong_Check(o)) {
        PyErr_SetString(PyExc_TypeError, "object cannot be interpreted as an integer");
        return 0;
    }
    Py_IncRef(o);
    return o;
}

PyObject *PyNumber_And(PyObject *a, PyObject *b) {
    long x, y;
    if (!py_as_long(a, &x) || !py_as_long(b, &y)) {
        PyErr_SetString(PyExc_TypeError, "unsupported operand type(s) for &");
        return 0;
    }
    return PyLong_FromLong(x & y);
}

PyObject *PyNumber_Rshift(PyObject *a, PyObject *b) {
    long x, y;
    if (!py_as_long(a, &x) || !py_as_long(b, &y)) {
        PyErr_SetString(PyExc_TypeError, "unsupported operand type(s) for >>");
        return 0;
    }
    return PyLong_FromLong(x >> y);
}

PyObject *PyNumber_Invert(PyObject *o) {
    long x;
    if (!py_as_long(o, &x)) {
        PyErr_SetString(PyExc_TypeError, "bad operand type for unary ~");
        return 0;
    }
    return PyLong_FromLong(~x);
}

/* --- object protocol ----------------------------------------------------- */
int PyObject_IsTrue(PyObject *o) {
    if (o == 0) return -1;
    if (o == Py_None) return 0;
    if (o->ob_kind == PYOBJ_LONG)  return o->ob_ival != 0;
    if (o->ob_kind == PYOBJ_FLOAT) return o->ob_fval != 0.0;
    if (o->ob_kind == PYOBJ_STR || o->ob_kind == PYOBJ_BYTES) return o->ob_size != 0;
    if (o->ob_kind == PYOBJ_TUPLE || o->ob_kind == PYOBJ_LIST ||
        o->ob_kind == PYOBJ_DICT) return o->ob_size != 0;
    return 1;
}

Py_hash_t PyObject_Hash(PyObject *o) {
    const unsigned char *p;
    Py_ssize_t i;
    Py_uhash_t h;
    if (o == 0) return -1;
    if (o->ob_kind == PYOBJ_LONG)  return (Py_hash_t)o->ob_ival;
    if (o->ob_kind == PYOBJ_FLOAT) return (Py_hash_t)(long)o->ob_fval;
    if (o->ob_kind == PYOBJ_STR || o->ob_kind == PYOBJ_BYTES) {
        /* FNV-1a. NOT CPython's siphash: hash values are never compared
           across the two runtimes, only used within one process. */
        h = 14695981039346656037UL;
        p = (const unsigned char *)o->ob_ptr;
        for (i = 0; i < o->ob_size; i++) {
            h = h ^ (Py_uhash_t)p[i];
            h = h * 1099511628211UL;
        }
        return (Py_hash_t)(h & 0x7fffffffffffffffUL);
    }
    PyErr_SetString(PyExc_TypeError, "unhashable type");
    return -1;
}

/* -1 error, 0 false, 1 true — three-valued, as CPython's is. */
int PyObject_RichCompareBool(PyObject *a, PyObject *b, int op) {
    long x, y;
    int c;
    if (a == 0 || b == 0) return -1;
    if (op == Py_EQ) return py_obj_eq(a, b);
    if (op == Py_NE) return !py_obj_eq(a, b);
    c = 0;
    if (py_as_long(a, &x) && py_as_long(b, &y))
        c = (x < y) ? -1 : ((x > y) ? 1 : 0);
    else if (a->ob_kind == PYOBJ_STR && b->ob_kind == PYOBJ_STR)
        c = strcmp((char *)a->ob_ptr, (char *)b->ob_ptr);
    else {
        PyErr_SetString(PyExc_TypeError, "'<' not supported between these types");
        return -1;
    }
    if (op == Py_LT) return c <  0;
    if (op == Py_LE) return c <= 0;
    if (op == Py_GT) return c >  0;
    return c >= 0;   /* Py_GE */
}

/* --- attributes ----------------------------------------------------------
   Modules, module SPECS and function objects carry a real attribute dict
   (ob_attrs, allocated on first write). Every other kind has none, and
   AttributeError is then not a placeholder — it is the correct Python answer
   for an object that does not carry the name, and it is what an extension's
   own optional-feature probe expects to see. */
static int py_has_attrs(PyObject *o) {
    return o != 0 && (o->ob_kind == PYOBJ_MODULE || o->ob_kind == PYOBJ_NS ||
                      o->ob_kind == PYOBJ_CFUNC);
}

static PyObject *py_attrs(PyObject *o) {
    if (!py_has_attrs(o)) return 0;
    if (o->ob_attrs == 0) o->ob_attrs = PyDict_New();
    return o->ob_attrs;
}

PyObject *PyObject_GetAttrString(PyObject *o, const char *name) {
    PyObject *d;
    PyObject *v;
    d = py_attrs(o);
    if (d != 0) {
        v = PyDict_GetItemString(d, name);   /* borrowed */
        if (v != 0) { Py_IncRef(v); return v; }
    }
    PyErr_SetString(PyExc_AttributeError, name);
    return 0;
}

PyObject *PyObject_GetAttr(PyObject *o, PyObject *name) {
    return PyObject_GetAttrString(o, PyUnicode_Check(name) ? (const char *)name->ob_ptr : "?");
}

int PyObject_SetAttrString(PyObject *o, const char *name, PyObject *v) {
    PyObject *d;
    d = py_attrs(o);
    if (d == 0) {
        PyErr_SetString(PyExc_AttributeError, name);
        return -1;
    }
    return PyDict_SetItemString(d, name, v);
}

int PyObject_SetAttr(PyObject *o, PyObject *name, PyObject *v) {
    return PyObject_SetAttrString(o, PyUnicode_Check(name) ? (const char *)name->ob_ptr : "?", v);
}

/* --- calling -------------------------------------------------------------
   Only a builtin-function object is callable. That covers what an extension
   actually needs (its own module-level functions, reached after Py_mod_exec
   registered them); calling back into arbitrary NilPy objects from C is a
   later milestone, and TypeError is what CPython says for a non-callable. */
PyObject *PyObject_Call(PyObject *callable, PyObject *args, PyObject *kwargs) {
    PyMethodDef *md;
    PyObject **fastargs;
    Py_ssize_t n;
    Py_ssize_t i;
    Py_ssize_t nkw;
    Py_ssize_t kwi;
    Py_ssize_t pos;
    PyObject *kwnames;
    PyObject *kwkey;
    PyObject *kwval;
    PyObject *r;
    int flags;

    if (callable == 0 || callable->ob_kind != PYOBJ_CFUNC) {
        PyErr_SetString(PyExc_TypeError, "object is not callable in this runtime");
        return 0;
    }
    md = (PyMethodDef *)callable->ob_ptr;
    flags = md->ml_flags;
    n = (args != 0) ? PyTuple_Size(args) : 0;
    if (n < 0) n = 0;

    /* METH_FASTCALL: the callee wants a C ARRAY of borrowed argument pointers
       plus a count, not a tuple. Generated code uses this for every function
       when the claimed version is 3.12+, so it is the common path, not an
       optimisation. kwnames NULL = no keyword arguments; passing keywords
       through the fast path needs the names tuple and is not wired up. */
    if ((flags & METH_FASTCALL) != 0) {
        /* The vectorcall layout: ONE array holding the positional arguments
           followed by the keyword VALUES, with `kwnames` a tuple of the matching
           keyword names. So keywords need no separate channel — they ride the
           same array past the positional count, which is why nargs and the array
           length differ once keywords are present.

           This used to refuse keywords outright. Refusing was the right call
           while the names tuple did not exist (mis-passing them would have been
           silent), but a Cython module's `f(a, b=2)` is ordinary code. */
        nkw = 0;
        kwnames = 0;
        if (kwargs != 0) {
            nkw = PyDict_Size(kwargs);
            if (nkw < 0) nkw = 0;
        }
        if (nkw > 0) {
            if ((flags & METH_KEYWORDS) == 0) {
                PyErr_SetString(PyExc_TypeError,
                                "function takes no keyword arguments");
                return 0;
            }
            kwnames = PyTuple_New(nkw);
            if (kwnames == 0) return 0;
        }
        fastargs = (PyObject **)malloc(
            (size_t)((n + nkw > 0 ? n + nkw : 1)) * sizeof(PyObject *));
        for (i = 0; i < n; i++) fastargs[i] = PyTuple_GetItem(args, i);  /* borrowed */
        if (nkw > 0) {
            /* PyDict_Next walks in insertion order here, and the names tuple must
               agree index-for-index with the values written past nargs — one walk
               fills both, so they cannot drift. */
            pos = 0;
            kwi = 0;
            while (PyDict_Next(kwargs, &pos, &kwkey, &kwval) && kwi < nkw) {
                Py_INCREF(kwkey);
                PyTuple_SetItem(kwnames, kwi, kwkey);   /* steals the reference */
                fastargs[n + kwi] = kwval;              /* borrowed, like above */
                kwi++;
            }
        }
        if ((flags & METH_KEYWORDS) != 0)
            r = ((PyCFunctionFastWithKeywords)md->ml_meth)(0, fastargs, n, kwnames);
        else
            r = ((PyCFunctionFast)md->ml_meth)(0, fastargs, n);
        free(fastargs);
        Py_XDECREF(kwnames);
        return r;
    }
    if ((flags & METH_KEYWORDS) != 0)
        return ((PyCFunctionWithKeywords)md->ml_meth)(0, args, kwargs);
    if (kwargs != 0 && PyDict_Size(kwargs) > 0) {
        PyErr_SetString(PyExc_TypeError, "function takes no keyword arguments");
        return 0;
    }
    if ((flags & METH_O) != 0)
        return md->ml_meth(0, PyTuple_GetItem(args, 0));
    if ((flags & METH_NOARGS) != 0)
        return md->ml_meth(0, 0);
    return md->ml_meth(0, args);
}

PyObject *PyObject_CallFunctionObjArgs(PyObject *callable, ...) {
    /* NULL-terminated PyObject* varargs -> a positional tuple -> PyObject_Call.
       Two passes over the list rather than a growing buffer: the count has to be
       known to size the tuple, and va_start may legally be used twice. The
       arguments are BORROWED by the caller's convention, and PyTuple_SetItem
       steals, so each one is retained on the way in and released with the
       tuple. */
    va_list ap;
    va_list ap2;
    PyObject *a;
    PyObject *tup;
    PyObject *r;
    Py_ssize_t n;
    Py_ssize_t i;

    n = 0;
    va_start(ap, callable);
    for (;;) {
        a = va_arg(ap, PyObject *);
        if (a == 0) break;
        n++;
    }
    va_end(ap);

    tup = PyTuple_New(n);
    if (tup == 0) return 0;
    va_start(ap2, callable);
    for (i = 0; i < n; i++) {
        a = va_arg(ap2, PyObject *);
        Py_INCREF(a);
        PyTuple_SetItem(tup, i, a);   /* steals */
    }
    va_end(ap2);

    r = PyObject_Call(callable, tup, 0);
    Py_DECREF(tup);
    return r;
}

/* --- tuple / bytes / bytearray ------------------------------------------- */
Py_ssize_t PyTuple_Size(PyObject *t) {
    if (t == 0 || t->ob_kind != PYOBJ_TUPLE) return -1;
    return t->ob_size;
}

int PyBytes_AsStringAndSize(PyObject *o, char **buf, Py_ssize_t *len) {
    if (o == 0 || o->ob_kind != PYOBJ_BYTES) {
        PyErr_SetString(PyExc_TypeError, "expected bytes");
        return -1;
    }
    *buf = (char *)o->ob_ptr;
    if (len != 0) *len = o->ob_size;
    return 0;
}

/* bytearray shares the bytes representation — this runtime has no mutable
   buffer type, so a bytearray is a bytes object with the same bytes. Correct
   for construction and reading; an in-place mutation through
   PyByteArray_AsString would be visible where CPython would also make it
   visible, so the shared storage is not itself a lie. */
PyObject *PyByteArray_FromStringAndSize(const char *s, Py_ssize_t n) {
    return PyBytes_FromStringAndSize(s, n);
}

char *PyByteArray_AsString(PyObject *o) {
    if (o == 0 || o->ob_kind != PYOBJ_BYTES) return 0;
    return (char *)o->ob_ptr;
}

Py_ssize_t PyByteArray_Size(PyObject *o) {
    if (o == 0 || o->ob_kind != PYOBJ_BYTES) return -1;
    return o->ob_size;
}

/* --- unicode ------------------------------------------------------------- */
int PyUnicode_Compare(PyObject *a, PyObject *b) {
    if (a == 0 || b == 0 || a->ob_kind != PYOBJ_STR || b->ob_kind != PYOBJ_STR) {
        PyErr_SetString(PyExc_TypeError, "Compare expected two str");
        return -1;
    }
    return strcmp((char *)a->ob_ptr, (char *)b->ob_ptr);
}

int PyUnicode_CompareWithASCIIString(PyObject *a, const char *s) {
    if (a == 0 || a->ob_kind != PYOBJ_STR) return -1;
    return strcmp((char *)a->ob_ptr, s);
}

/* UTF-8 only, and only because that is what this runtime's strings ARE.
   Any other encoding is refused rather than silently treated as UTF-8. */
PyObject *PyUnicode_DecodeUTF8(const char *s, Py_ssize_t size, const char *errors) {
    (void)errors;
    return PyUnicode_FromStringAndSize(s, size);
}

PyObject *PyUnicode_Decode(const char *s, Py_ssize_t size,
                           const char *encoding, const char *errors) {
    if (encoding != 0 && strcmp(encoding, "utf-8") != 0 &&
        strcmp(encoding, "UTF-8") != 0 && strcmp(encoding, "ascii") != 0) {
        PyErr_SetString(PyExc_ValueError, "only utf-8/ascii decoding is supported");
        return 0;
    }
    return PyUnicode_DecodeUTF8(s, size, errors);
}

PyObject *PyUnicode_FromFormat(const char *format, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, format);
    /* Same printf superset as PyErr_Format — CPython documents %U %S %R %A for
       this function too, so it had the identical vsnprintf bug. (PyOS_snprintf
       below deliberately keeps vsnprintf: CPython documents THAT one as a plain
       snprintf wrapper, with no object specifiers.) */
    __pxx_cpyext_vformat(buf, sizeof(buf), format, ap);
    va_end(ap);
    return PyUnicode_FromString(buf);
}

/* No interning table: returning the string unchanged is a valid
   implementation of interning (it only promises identity for EQUAL strings
   that were both interned, and nothing here relies on that). */
void PyUnicode_InternInPlace(PyObject **p) { (void)p; }

/* --- dict ---------------------------------------------------------------- */
int PyDict_Contains(PyObject *d, PyObject *key) {
    if (d == 0 || d->ob_kind != PYOBJ_DICT) return -1;
    return PyDict_GetItem(d, key) != 0;
}

PyObject *PyDict_GetItemString(PyObject *d, const char *key) {
    PyObject *k;
    PyObject *v;
    k = PyUnicode_FromString(key);
    v = PyDict_GetItem(d, k);   /* borrowed */
    Py_DecRef(k);
    return v;
}

/* CPython's _WithError differs from PyDict_GetItem only in propagating a
   lookup error; nothing here can fail a lookup, so they coincide. */
PyObject *PyDict_GetItemWithError(PyObject *d, PyObject *key) {
    return PyDict_GetItem(d, key);
}

int PyDict_SetItemString(PyObject *d, const char *key, PyObject *v) {
    PyObject *k;
    int r;
    k = PyUnicode_FromString(key);
    r = PyDict_SetItem(d, k, v);
    Py_DecRef(k);
    return r;
}

int PyDict_Update(PyObject *a, PyObject *b) {
    Py_ssize_t pos;
    PyObject *k;
    PyObject *v;
    if (a == 0 || b == 0 || a->ob_kind != PYOBJ_DICT || b->ob_kind != PYOBJ_DICT) {
        PyErr_SetString(PyExc_TypeError, "update expected two dicts");
        return -1;
    }
    pos = 0;
    while (PyDict_Next(b, &pos, &k, &v)) {
        if (PyDict_SetItem(a, k, v) != 0) return -1;
    }
    return 0;
}

/* --- errors --------------------------------------------------------------
   The pending-error slot is a single (type, message) pair — see PyErr_SetString
   above. Fetch/Restore therefore move the TYPE and drop the value/traceback,
   which is why both are documented here rather than looking complete. */
int PyErr_GivenExceptionMatches(PyObject *given, PyObject *exc) {
    return given != 0 && given == exc;
}

int PyErr_ExceptionMatches(PyObject *exc) {
    return PyErr_GivenExceptionMatches(PyErr_Occurred(), exc);
}

/* The pending-error slot is a single (type, message) pair — see PyErr_SetString.
   Fetch hands the message back as a real str object so that the pair survives
   a Fetch/Restore round trip: generated code fetches the current exception,
   does something (build a traceback), then restores it, and losing the message
   there turns a reportable error into an empty one. That is exactly what
   happened while bringing this up — the first Cython import failure reported
   nothing at all. There is still no traceback object, and *ptraceback is NULL. */
void PyErr_Fetch(PyObject **ptype, PyObject **pvalue, PyObject **ptraceback) {
    if (ptype != 0) *ptype = PyErr_Occurred();
    if (pvalue != 0) *pvalue = PyUnicode_FromString(__pxx_PyErr_Message());
    if (ptraceback != 0) *ptraceback = 0;
    PyErr_Clear();
}

void PyErr_Restore(PyObject *type, PyObject *value, PyObject *traceback) {
    (void)traceback;
    if (type == 0) { PyErr_Clear(); return; }
    PyErr_SetString(type, (value != 0 && PyUnicode_Check(value))
                            ? (const char *)value->ob_ptr : "");
}

/* CPython's PyErr_Format accepts a SUPERSET of printf: %U is a PyObject* that
   must be a str, %S is str() of any object, %R is repr(), %A is ascii(). glibc
   knows none of them — it printed them literally AND consumed no argument, so
   every specifier after one read the wrong va_arg. An extension's own
   "unexpected keyword argument '%U'" came out with the %U still in it, and a
   message mixing %U with %d printed a garbage number
   (bug-cpyext-pyerr-format-prints-U-and-S-literally).

   So the format is walked here, and each PASS-THROUGH specifier is handed to
   snprintf on its own — number and width formatting stays the C library's job
   rather than being reimplemented. Only the object specifiers are rendered
   locally.

   One function shared by PyErr_Format and PyErr_WarnFormat, which had identical
   bodies and therefore the identical bug; taking va_list as a parameter is
   confirmed to work through cfront. */
static void obj_text(PyObject *o, int quoted, char *out, size_t cap) {
    const char *s;

    if (cap == 0) return;
    out[0] = 0;
    if (o == 0) { snprintf(out, cap, "<NULL>"); return; }
    switch (o->ob_kind) {
        case PYOBJ_STR:
            s = (const char *)o->ob_ptr;
            if (s == 0) s = "";
            if (quoted) snprintf(out, cap, "'%s'", s);
            else snprintf(out, cap, "%s", s);
            return;
        case PYOBJ_BYTES:
            s = (const char *)o->ob_ptr;
            if (s == 0) s = "";
            snprintf(out, cap, "b'%s'", s);
            return;
        case PYOBJ_LONG:  snprintf(out, cap, "%ld", o->ob_ival); return;
        case PYOBJ_FLOAT: snprintf(out, cap, "%g", o->ob_fval); return;
        case PYOBJ_NONE:  snprintf(out, cap, "None"); return;
        case PYOBJ_TUPLE: snprintf(out, cap, "<tuple>"); return;
        case PYOBJ_LIST:  snprintf(out, cap, "<list>"); return;
        case PYOBJ_DICT:  snprintf(out, cap, "<dict>"); return;
        case PYOBJ_MODULE: snprintf(out, cap, "<module>"); return;
        case PYOBJ_CFUNC: snprintf(out, cap, "<built-in function>"); return;
        default:
            /* Named by KIND rather than left empty: a message that identifies
               something beats one that identifies nothing. */
            snprintf(out, cap, "<object kind %d>", o->ob_kind);
            return;
    }
}

void __pxx_cpyext_vformat(char *buf, size_t cap, const char *format, va_list ap) {
    size_t out;
    int i, j;
    char spec[32];
    char piece[256];
    PyObject *o;

    out = 0;
    i = 0;
    if (cap == 0) return;
    buf[0] = 0;
    while (format[i] != 0 && out + 1 < cap) {
        if (format[i] != '%') { buf[out] = format[i]; out = out + 1; i = i + 1; continue; }
        if (format[i + 1] == '%') { buf[out] = '%'; out = out + 1; i = i + 2; continue; }

        /* copy the whole specifier: flags, width, precision, length modifiers,
           then the conversion letter */
        j = 0;
        spec[j] = format[i]; j = j + 1; i = i + 1;
        while (format[i] != 0 && j < 24 &&
               (format[i] == '-' || format[i] == '+' || format[i] == ' ' ||
                format[i] == '#' || format[i] == '0' || format[i] == '.' ||
                (format[i] >= '1' && format[i] <= '9') ||
                format[i] == 'l' || format[i] == 'z' || format[i] == 'h')) {
            spec[j] = format[i]; j = j + 1; i = i + 1;
        }
        if (format[i] == 0) break;
        spec[j] = format[i]; j = j + 1;
        spec[j] = 0;
        piece[0] = 0;

        switch (format[i]) {
            case 'U':                      /* PyObject* known to be a str */
            case 'S':                      /* str() of any object */
                o = va_arg(ap, PyObject *);
                obj_text(o, 0, piece, sizeof(piece));
                break;
            case 'R':                      /* repr() */
            case 'A':                      /* ascii(); this runtime is byte-only,
                                              so identical to repr here */
                o = va_arg(ap, PyObject *);
                obj_text(o, 1, piece, sizeof(piece));
                break;
            case 's':
                snprintf(piece, sizeof(piece), spec, va_arg(ap, const char *));
                break;
            case 'p':
                snprintf(piece, sizeof(piece), spec, va_arg(ap, void *));
                break;
            case 'c':
                snprintf(piece, sizeof(piece), spec, va_arg(ap, int));
                break;
            case 'd': case 'i': case 'u': case 'x': case 'X': case 'o':
                /* the length modifier decides the argument's width, and reading
                   an `int` for a %ld would misalign the rest of the list */
                if ((j >= 3) && (spec[j - 2] == 'l' || spec[j - 2] == 'z'))
                    snprintf(piece, sizeof(piece), spec, va_arg(ap, long));
                else
                    snprintf(piece, sizeof(piece), spec, va_arg(ap, int));
                break;
            case 'f': case 'g': case 'e': case 'G': case 'E':
                snprintf(piece, sizeof(piece), spec, va_arg(ap, double));
                break;
            default:
                /* Unknown conversion: emit it verbatim and consume NOTHING,
                   which is what glibc effectively did. Kept deliberate rather
                   than guessing an argument width, since guessing wrong
                   misaligns everything after it. */
                snprintf(piece, sizeof(piece), "%s", spec);
                break;
        }
        i = i + 1;

        j = 0;
        while (piece[j] != 0 && out + 1 < cap) { buf[out] = piece[j]; out = out + 1; j = j + 1; }
    }
    buf[out] = 0;
}

PyObject *PyErr_Format(PyObject *exc, const char *format, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, format);
    __pxx_cpyext_vformat(buf, sizeof(buf), format, ap);
    va_end(ap);
    PyErr_SetString(exc, buf);
    return 0;   /* always NULL, as CPython's does */
}

/* Warnings go to stderr. There is no warnings module to filter them, so they
   are never suppressed and never turned into errors; 0 means "not raised as
   an error", which is the answer callers act on. */
int PyErr_WarnEx(PyObject *category, const char *message, Py_ssize_t stacklevel) {
    (void)category; (void)stacklevel;
    fprintf(stderr, "pxx cpyext warning: %s\n", message);
    return 0;
}

int PyErr_WarnFormat(PyObject *category, Py_ssize_t stacklevel,
                     const char *format, ...) {
    char buf[512];
    va_list ap;
    (void)category; (void)stacklevel;
    va_start(ap, format);
    __pxx_cpyext_vformat(buf, sizeof(buf), format, ap);   /* same superset */
    va_end(ap);
    fprintf(stderr, "pxx cpyext warning: %s\n", buf);
    return 0;
}

/* --- raw memory ---------------------------------------------------------- */
void *PyMem_Malloc(size_t n)             { return malloc(n); }
void *PyMem_Realloc(void *p, size_t n)   { return realloc(p, n); }
void  PyMem_Free(void *p)                { free(p); }

/* --- argument plumbing --------------------------------------------------- */
int PyArg_ValidateKeywordArguments(PyObject *kwargs) {
    if (kwargs == 0) return 1;
    if (kwargs->ob_kind != PYOBJ_DICT) {
        PyErr_SetString(PyExc_TypeError, "keyword arguments must be a dict");
        return 0;
    }
    return 1;
}

/* --- module / import / sys ------------------------------------------------
   A pxx program links its modules in; there is no import machinery to consult
   at run time. The ONE exception is `builtins`, which generated code fetches
   unconditionally at module-exec time and would otherwise fail on — it is a
   real (empty) module here, so a name looked up in it raises AttributeError,
   which is the same answer Python gives for a name builtins does not have. */
PyObject *PyModule_GetDict(PyObject *m) {
    return py_attrs(m);     /* borrowed */
}

PyObject *PyModule_NewObject(PyObject *name) {
    PyObject *m;
    m = py_alloc(PYOBJ_MODULE);
    m->ob_ptr = 0;
    m->ob_size = 0;
    if (name != 0) PyObject_SetAttrString(m, "__name__", name);
    return m;
}

/* The module registry — CPython's sys.modules, minus the importer. */
static PyObject *g_modules = 0;

static PyObject *py_modules(void) {
    if (g_modules == 0) g_modules = PyDict_New();
    return g_modules;
}

/* CPython's PyImport_AddModule does NOT import: it returns the module of that
   name if one exists and otherwise CREATES an empty one and registers it.
   That is the whole contract, and it is one this runtime can honour exactly —
   which matters, because generated code uses it for `builtins` and for
   Cython's own `cython_runtime` scratch module, neither of which is importable
   from anywhere. */
PyObject *PyImport_AddModule(const char *name) {
    PyObject *m;
    PyObject *nm;
    m = PyDict_GetItemString(py_modules(), name);   /* borrowed */
    if (m != 0) return m;
    nm = PyUnicode_FromString(name);
    m = PyModule_NewObject(nm);
    PyDict_SetItemString(py_modules(), name, m);
    Py_DecRef(nm);
    Py_DecRef(m);          /* the registry holds the reference */
    return PyDict_GetItemString(py_modules(), name);
}

PyObject *PyImport_GetModuleDict(void) {
    return py_modules();   /* borrowed */
}

/* ...whereas PyImport_ImportModule really does import, and there is no
   importer here: a pxx program links its modules in. A name already in the
   registry is returned; anything else is an honest ImportError, which is what
   an extension's optional-dependency probe expects. */
PyObject *PyImport_ImportModule(const char *name) {
    PyObject *m;
    m = PyDict_GetItemString(py_modules(), name);
    if (m == 0) {
        PyErr_SetString(PyExc_ImportError, name);
        return 0;
    }
    Py_IncRef(m);
    return m;
}

PyObject *PySys_GetObject(const char *name) {
    (void)name;
    return 0;
}

/* --- builtin-function objects --------------------------------------------
   A PyMethodDef entry wrapped as a callable. This is what Cython's module
   exec builds for every module-level `def` — with an EMPTY m_methods table,
   it is the only route by which those functions become reachable. */
PyObject *PyCFunction_New(PyMethodDef *ml, PyObject *self) {
    return PyCFunction_NewEx(ml, self, 0);
}

PyObject *PyCFunction_NewEx(PyMethodDef *ml, PyObject *self, PyObject *module) {
    PyObject *f;
    (void)self;   /* no bound builtins in this model */
    f = py_alloc(PYOBJ_CFUNC);
    f->ob_ptr = (void *)ml;
    if (ml != 0 && ml->ml_name != 0) {
        PyObject *nm;
        nm = PyUnicode_FromString(ml->ml_name);
        PyObject_SetAttrString(f, "__name__", nm);
        Py_DecRef(nm);
    }
    if (module != 0) PyObject_SetAttrString(f, "__module__", module);
    return f;
}

PyCFunction PyCFunction_GetFunction(PyObject *op) {
    if (op == 0 || op->ob_kind != PYOBJ_CFUNC) {
        PyErr_SetString(PyExc_TypeError, "expected a builtin function");
        return 0;
    }
    return ((PyMethodDef *)op->ob_ptr)->ml_meth;
}

/* --- interpreter identity -------------------------------------------------
   There is exactly one interpreter and it is implicit, so a fixed non-NULL
   handle and id 0 are not stubs — they are the true answer. Generated code
   uses them only to refuse a SECOND interpreter, which cannot occur. */
static int g_the_interpreter = 0;

void *PyInterpreterState_Get(void) {
    return (void *)&g_the_interpreter;
}

long long PyInterpreterState_GetID(void *interp) {
    (void)interp;
    return 0;
}

int PyOS_snprintf(char *str, size_t size, const char *format, ...) {
    int n;
    va_list ap;
    va_start(ap, format);
    n = vsnprintf(str, size, format, ap);
    va_end(ap);
    return n;
}

/* --- reachable only if something really calls them ------------------------
   Each of these is referenced by generated utility code that a
   compiled-ahead-of-time extension does not execute, so they must LINK; but
   there is no honest value to return, so reaching one stops the program with
   its name. See RULE 2 at the top of this section. */
/* No Python compiler here. This one does NOT stop the program, deliberately:
   its only caller in practice is Cython's traceback DECORATOR
   (__Pyx_AddTraceback), which compiles "_getframe()" to synthesize a code
   object. Failing that must not kill the process — it is optional decoration
   over an exception that has already happened, and the caller restores the
   original exception when this returns NULL. Stopping here would replace a
   real, reportable error with a message about tracebacks, which is how the
   first Cython import failure got misread. */
struct _object *Py_CompileString(const char *str, const char *filename, int start) {
    (void)str; (void)filename; (void)start;
    PyErr_SetString(PyExc_RuntimeError, "no Python compiler in this runtime");
    return 0;
}
PyObject *PyEval_EvalCode(PyObject *co, PyObject *globals, PyObject *locals) {
    (void)co; (void)globals; (void)locals;
    __pxx_cpyext_unsupported("PyEval_EvalCode"); return 0;
}
/* Same reasoning as Py_CompileString: traceback recording is decoration over
   an exception that already exists. There is no traceback object to append a
   frame to, so it reports failure and the caller carries on. */
int PyTraceBack_Here(void *frame) {
    (void)frame;
    return -1;
}
PyObject *PyType_GetQualName(PyTypeObject *t) {
    (void)t; __pxx_cpyext_unsupported("PyType_GetQualName"); return 0;
}
PyObject *PyObject_Vectorcall(PyObject *callable, PyObject *const *args,
                              size_t nargsf, PyObject *kwnames) {
    (void)callable; (void)args; (void)nargsf; (void)kwnames;
    __pxx_cpyext_unsupported("PyObject_Vectorcall"); return 0;
}
PyObject *PyObject_VectorcallMethod(PyObject *name, PyObject *const *args,
                                    size_t nargsf, PyObject *kwnames) {
    (void)name; (void)args; (void)nargsf; (void)kwnames;
    __pxx_cpyext_unsupported("PyObject_VectorcallMethod"); return 0;
}
Py_ssize_t PyVectorcall_NARGS(size_t nargsf) {
    return (Py_ssize_t)(nargsf & ~PY_VECTORCALL_ARGUMENTS_OFFSET);
}
PyObject *PyMemoryView_FromMemory(char *mem, Py_ssize_t size, int flags) {
    (void)mem; (void)size; (void)flags;
    __pxx_cpyext_unsupported("PyMemoryView_FromMemory"); return 0;
}

/* --- PEP 489 multi-phase module init -------------------------------------
   Previously collapsed to PyModule_Create2, which was fine while every
   extension put its functions in a static m_methods table. Cython 3 does not:
   `__pyx_methods` is EMPTY and the module-level defs are registered from the
   Py_mod_exec slot, so a collapsed init produced a module with no functions
   at all — a silently empty module, which is the failure mode this runtime
   refuses everywhere else. So the slots are now actually run.

   This is a small piece of the import machinery, deliberately: create the
   module (Py_mod_create if given, else the default), then execute every
   Py_mod_exec in order and fail if one does. The SPEC object the create slot
   receives is synthesized here — real CPython's importlib builds it, and the
   only field generated code reads is `name`. Unknown slot ids are capability
   announcements (Py_mod_gil, Py_mod_multiple_interpreters) and are ignored;
   an unknown slot that mattered would announce itself by the module not
   working, not by being silently wrong. */
PyObject *PyModuleDef_Init(PyModuleDef *def) {
    PyObject *spec;
    PyObject *nm;
    PyObject *module;
    PyModuleDef_Slot *slot;
    PyObject *(*createfn)(PyObject *, PyModuleDef *);
    int (*execfn)(PyObject *);

    module = 0;
    spec = py_alloc(PYOBJ_NS);
    nm = PyUnicode_FromString(def->m_name != 0 ? def->m_name : "");
    PyObject_SetAttrString(spec, "name", nm);
    Py_DecRef(nm);

    if (def->m_slots != 0) {
        for (slot = def->m_slots; slot->slot != 0; slot++) {
            if (slot->slot == Py_mod_create) {
                createfn = (PyObject *(*)(PyObject *, PyModuleDef *))slot->value;
                module = createfn(spec, def);
                if (module == 0) { Py_DecRef(spec); return 0; }
            }
        }
    }
    if (module == 0) module = PyModule_Create2(def, 0);
    if (module == 0) { Py_DecRef(spec); return 0; }

    if (def->m_slots != 0) {
        for (slot = def->m_slots; slot->slot != 0; slot++) {
            if (slot->slot == Py_mod_exec) {
                execfn = (int (*)(PyObject *))slot->value;
                if (execfn(module) < 0) {
                    Py_DecRef(module);
                    Py_DecRef(spec);
                    return 0;
                }
                /* A slot that reports SUCCESS may still have left an error
                   pending, and Cython does exactly that: its
                   __Pyx_init_co_variables calls PyImport_ImportModule("inspect")
                   UNCONDITIONALLY, then only reads the result for CO_* flags it
                   could not get as macros. Our Python.h defines all of them, so
                   every use is preprocessed out, `result` stays 1, and the failed
                   import's ImportError is simply abandoned. Under real CPython
                   the import succeeds, so the extension never notices.

                   Leaving it pending is not harmless: the next Cython code to
                   consult PyErr_Occurred() as its own error check fails on
                   somebody else's stale error. Measured — `cysub(a=30, b=8)`
                   returned -1 with the message "inspect", while the same call
                   with one positional argument worked, because only the
                   all-keyword path reached such a check. Clearing here made all
                   of them pass.

                   A successful init that leaves an error set is the extension
                   violating the contract, so discarding it is the honest repair
                   at exactly the boundary that knows init succeeded. */
                if (PyErr_Occurred() != 0) PyErr_Clear();
            }
        }
    }
    Py_DecRef(spec);
    return module;
}
