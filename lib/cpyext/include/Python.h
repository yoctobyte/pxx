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
 * M1 ("hello-ext") scope only: a one-int-argument, one-int-return function
 * exposed through a real PyModuleDef/PyMethodDef table and PyInit_<name>.
 * Grow this header only as a later milestone's extension needs more surface;
 * an API this header does not implement should fail to LINK (undefined
 * symbol), never silently do nothing at runtime.
 */

#include <stdarg.h>
#include <stddef.h>

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

typedef struct _object {
    long  ob_refcnt;
    int   ob_kind;   /* PYOBJ_* above */
    long  ob_ival;   /* PYOBJ_LONG payload */
    void *ob_ptr;    /* PYOBJ_TUPLE: PyObject** items; PYOBJ_MODULE: PyMethodDef* */
    long  ob_size;   /* PYOBJ_TUPLE: item count; PYOBJ_MODULE: method count */
} PyObject;

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

/* --- int conversion ------------------------------------------------------ */
PyObject *PyLong_FromLong(long v);
long PyLong_AsLong(PyObject *o);

/* --- tuples: enough to carry PyArg_ParseTuple's positional args --------- */
PyObject *PyTuple_New(Py_ssize_t n);
int PyTuple_SetItem(PyObject *t, Py_ssize_t i, PyObject *v); /* steals v */
PyObject *PyTuple_GetItem(PyObject *t, Py_ssize_t i);        /* borrowed */

/* --- argument parsing: format spec "i" only for M1 ----------------------- */
int PyArg_ParseTuple(PyObject *args, const char *format, ...);

/* --- module definition ---------------------------------------------------- */
typedef PyObject *(*PyCFunction)(PyObject *self, PyObject *args);

#define METH_VARARGS 0x0001

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

typedef struct PyModuleDef {
    PyModuleDef_Base m_base;
    const char      *m_name;
    const char      *m_doc;
    Py_ssize_t       m_size;
    PyMethodDef     *m_methods;
} PyModuleDef;

PyObject *PyModule_Create2(PyModuleDef *def, int module_api_version);
#define PyModule_Create(def) PyModule_Create2((def), 1013)

#define PyMODINIT_FUNC PyObject *

#endif /* PXX_CPYEXT_PYTHON_H */
