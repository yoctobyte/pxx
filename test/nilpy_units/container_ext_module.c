/* M3 "strings and containers" milestone (feature-nilpy-cpyext-c-api-from-source):
 * a hand-written CPython extension exercising list/tuple/dict construction
 * and iteration, plus Unicode/bytes round-trip, in the ordinary shape a real
 * extension takes. Compiled by cfront against lib/cpyext/include/Python.h.
 *
 * Scope note (see the M3 comment atop lib/cpyext/include/Python.h and the
 * ticket's M3 entry): the containers built here are entirely internal to
 * this extension's C code — every PyMethodDef entry point still crosses the
 * NilPy boundary as a scalar/string, same as M1/M2. Not named
 * container_ext.c on purpose — see argerr_ext.pas's comment on the same
 * basename-collision hazard (bug-c-uses-path-basename-collides-with-enclosing-unit-name). */

#include <Python.h>

/* PyList_New/SetItem/GetItem: build [0, 1, ..., n-1] then sum it back by
 * iterating with PyList_GetItem. Proves list construction + iteration. */
static PyObject *
container_sum_range(PyObject *self, PyObject *args)
{
    int n, i;
    long total;
    PyObject *lst;
    PyObject *item;

    if (!PyArg_ParseTuple(args, "i", &n))
        return NULL;
    if (n < 0) {
        PyErr_SetString(PyExc_ValueError, "n must be non-negative");
        return NULL;
    }
    lst = PyList_New(n);
    for (i = 0; i < n; i++)
        PyList_SetItem(lst, i, PyLong_FromLong((long)i));
    total = 0;
    for (i = 0; i < (int)PyList_Size(lst); i++) {
        item = PyList_GetItem(lst, i);
        total = total + PyLong_AsLong(item);
    }
    Py_DECREF(lst);
    return Py_BuildValue("l", total);
}

/* PyList_Append: split a comma-separated string, build a Python list of the
 * PIECE LENGTHS via repeated Append, then join them back into "a,b,c" by
 * iterating the list. Proves append + iteration together. */
static PyObject *
container_join_lengths(PyObject *self, PyObject *args)
{
    const char *csv;
    char out[256];
    int oi, i, start, n;
    PyObject *lst;
    PyObject *item;

    if (!PyArg_ParseTuple(args, "s", &csv))
        return NULL;
    lst = PyList_New(0);
    start = 0;
    i = 0;
    while (1) {
        if (csv[i] == ',' || csv[i] == 0) {
            PyList_Append(lst, PyLong_FromLong((long)(i - start)));
            if (csv[i] == 0) break;
            start = i + 1;
        }
        i = i + 1;
    }
    oi = 0;
    n = (int)PyList_Size(lst);
    for (i = 0; i < n; i++) {
        char buf[16];
        int bi, v;
        item = PyList_GetItem(lst, i);
        v = (int)PyLong_AsLong(item);
        bi = 0;
        if (v == 0) { buf[bi] = '0'; bi = bi + 1; }
        while (v > 0) { buf[bi] = (char)('0' + (v % 10)); v = v / 10; bi = bi + 1; }
        while (bi > 0) { bi = bi - 1; out[oi] = buf[bi]; oi = oi + 1; }
        if (i + 1 < n) { out[oi] = ','; oi = oi + 1; }
    }
    out[oi] = 0;
    Py_DECREF(lst);
    return Py_BuildValue("s", out);
}

/* PyDict_New/SetItem/GetItem/Next: a character histogram, insertion-order
 * iterated back into "c:n,c:n,...". Proves dict construction + iteration. */
static PyObject *
container_char_histogram(PyObject *self, PyObject *args)
{
    const char *s;
    PyObject *dict;
    PyObject *key;
    PyObject *cur;
    char kbuf[2];
    Py_ssize_t pos;
    PyObject *pkey;
    PyObject *pval;
    char out[256];
    int oi, first;

    if (!PyArg_ParseTuple(args, "s", &s))
        return NULL;
    dict = PyDict_New();
    kbuf[1] = 0;
    while (*s != 0) {
        kbuf[0] = *s;
        key = PyUnicode_FromStringAndSize(kbuf, 1);
        cur = PyDict_GetItem(dict, key);
        if (cur == 0)
            PyDict_SetItem(dict, key, PyLong_FromLong(1));
        else
            PyDict_SetItem(dict, key, PyLong_FromLong(PyLong_AsLong(cur) + 1));
        Py_DECREF(key);
        s = s + 1;
    }
    oi = 0;
    first = 1;
    pos = 0;
    while (PyDict_Next(dict, &pos, &pkey, &pval)) {
        const char *ks;
        int v, bi;
        char buf[16];
        if (!first) { out[oi] = ','; oi = oi + 1; }
        first = 0;
        ks = PyUnicode_AsUTF8(pkey);
        out[oi] = ks[0];
        oi = oi + 1;
        out[oi] = ':';
        oi = oi + 1;
        v = (int)PyLong_AsLong(pval);
        bi = 0;
        if (v == 0) { buf[bi] = '0'; bi = bi + 1; }
        while (v > 0) { buf[bi] = (char)('0' + (v % 10)); v = v / 10; bi = bi + 1; }
        while (bi > 0) { bi = bi - 1; out[oi] = buf[bi]; oi = oi + 1; }
    }
    out[oi] = 0;
    Py_DECREF(dict);
    return Py_BuildValue("s", out);
}

/* PyBytes_FromStringAndSize/AsString/Size: round-trip a bytes-like ("y#")
 * argument through an actual PYOBJ_BYTES object (distinct from PYOBJ_STR)
 * and report what came back out. */
static PyObject *
container_bytes_roundtrip(PyObject *self, PyObject *args)
{
    const char *data;
    Py_ssize_t len;
    PyObject *bytesObj;
    char *back;
    Py_ssize_t backLen;
    char out[300];
    int oi, i;

    if (!PyArg_ParseTuple(args, "y#", &data, &len))
        return NULL;
    bytesObj = PyBytes_FromStringAndSize(data, len);
    back = PyBytes_AsString(bytesObj);
    backLen = PyBytes_Size(bytesObj);
    oi = 0;
    {
        char buf[16];
        int bi;
        long v;
        v = (long)backLen;
        bi = 0;
        if (v == 0) { buf[bi] = '0'; bi = bi + 1; }
        while (v > 0) { buf[bi] = (char)('0' + (v % 10)); v = v / 10; bi = bi + 1; }
        while (bi > 0) { bi = bi - 1; out[oi] = buf[bi]; oi = oi + 1; }
    }
    out[oi] = ':'; oi = oi + 1;
    for (i = 0; i < backLen; i++) { out[oi] = back[i]; oi = oi + 1; }
    out[oi] = 0;
    Py_DECREF(bytesObj);
    return Py_BuildValue("s", out);
}

static PyMethodDef ContainerMethods[] = {
    {"sum_range", container_sum_range, METH_VARARGS, "Sum 0..n-1 via a Python list."},
    {"join_lengths", container_join_lengths, METH_VARARGS, "Comma-split lengths via list append."},
    {"char_histogram", container_char_histogram, METH_VARARGS, "Character counts via a Python dict."},
    {"bytes_roundtrip", container_bytes_roundtrip, METH_VARARGS, "Round-trip through PyBytes_*."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef containermodule = {
    PyModuleDef_HEAD_INIT,
    "container_ext",
    NULL,
    -1,
    ContainerMethods
};

PyMODINIT_FUNC
PyInit_container_ext(void)
{
    return PyModule_Create(&containermodule);
}
