/* SPDX-License-Identifier: Zlib */
/* Implementation behind lib/cpyext/include/Python.h — see that file and
 * lib/cpyext/README.md. A tiny tagged-object model (long / float / string /
 * tuple / module / none) with refcounting.
 *
 * M1 "hello-ext": alloc/refcount, PyLong_*, PyTuple_*, PyArg_ParseTuple "i",
 * PyModule_Create2.
 * M2 "arguments and errors": PyFloat_*, PyUnicode_*, PyArg_ParseTuple /
 * Py_BuildValue widened to "i l d s s# O", and a pending-error slot behind
 * PyErr_SetString/PyErr_Occurred/PyErr_Clear. */

#include <Python.h>
#include <stdlib.h>
#include <string.h>

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
    return o;
}

void Py_IncRef(PyObject *o) {
    if (o == 0) return;
    o->ob_refcnt = o->ob_refcnt + 1;
}

void Py_DecRef(PyObject *o) {
    if (o == 0) return;
    if (o == &_Py_NoneStruct) return;
    if (o == &g_exc_exception || o == &g_exc_valueerror ||
        o == &g_exc_typeerror || o == &g_exc_runtimeerror) return;
    o->ob_refcnt = o->ob_refcnt - 1;
    if (o->ob_refcnt <= 0) {
        if ((o->ob_kind == PYOBJ_TUPLE || o->ob_kind == PYOBJ_STR) &&
            o->ob_ptr != 0)
            free(o->ob_ptr);
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
        } else if (c == 's') {
            sdst = va_arg(ap, const char **);
            if (item == 0 || item->ob_kind != PYOBJ_STR) {
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
        } else if (c == 's') {
            sval = va_arg(ap, const char *);
            if (format[fi + 1] == '#') {
                slen = va_arg(ap, Py_ssize_t);
                items[n] = PyUnicode_FromStringAndSize(sval, slen);
                fi = fi + 1;
            } else {
                items[n] = PyUnicode_FromString(sval);
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
    o = py_alloc(PYOBJ_MODULE);
    o->ob_ptr = (void *)def->m_methods;
    count = 0;
    while (def->m_methods[count].ml_name != 0) count = count + 1;
    o->ob_size = count;
    return o;
}
