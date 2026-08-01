/* SPDX-License-Identifier: Zlib */
/* Implementation behind lib/cpyext/include/Python.h — see that file and
 * lib/cpyext/README.md. A tiny tagged-object model (long / tuple / module /
 * none) with refcounting, just enough for M1 "hello-ext". */

#include <Python.h>
#include <stdlib.h>
#include <string.h>

PyObject _Py_NoneStruct = { 1, PYOBJ_NONE, 0, 0, 0 };

static PyObject *py_alloc(int kind) {
    PyObject *o;
    o = (PyObject *)malloc(sizeof(PyObject));
    o->ob_refcnt = 1;
    o->ob_kind = kind;
    o->ob_ival = 0;
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
    o->ob_refcnt = o->ob_refcnt - 1;
    if (o->ob_refcnt <= 0) {
        if (o->ob_kind == PYOBJ_TUPLE && o->ob_ptr != 0) free(o->ob_ptr);
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
    return o->ob_ival;
}

PyObject *PyTuple_New(Py_ssize_t n) {
    PyObject *o;
    PyObject **items;
    Py_ssize_t cap;
    Py_ssize_t i;
    o = py_alloc(PYOBJ_TUPLE);
    cap = (n > 0) ? n : 1;
    items = (PyObject **)malloc(sizeof(PyObject *) * cap);
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
    int idx;
    int ok;
    PyObject *item;
    int *dst;

    idx = 0;
    ok = 1;
    va_start(ap, format);
    while (format[idx] != 0) {
        if (format[idx] == 'i') {
            item = PyTuple_GetItem(args, idx);
            dst = va_arg(ap, int *);
            if (item == 0 || item->ob_kind != PYOBJ_LONG) {
                ok = 0;
            } else {
                *dst = (int)item->ob_ival;
            }
        } else {
            /* Unsupported format char for M1 — fail loudly, not silently. */
            ok = 0;
        }
        idx = idx + 1;
    }
    va_end(ap);
    return ok;
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
