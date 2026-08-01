/* M3 "strings and containers" driver: same shape as hello_ext_host.c (M1)
 * and argerr_ext_host.c (M2) — discover PyInit_container_ext, walk its
 * PyMethodDef table, call under the real PyCFunction(self, args)
 * convention. Every entry point here still crosses the Pascal-facing
 * boundary as plain scalars/strings (see the scope note atop
 * container_ext_module.c). */

#include <Python.h>
#include <string.h>

extern PyObject *PyInit_container_ext(void);

static PyCFunction find_method(PyObject *module, const char *name) {
    PyMethodDef *methods;
    long i;

    if (module == 0 || module->ob_kind != PYOBJ_MODULE) return 0;
    methods = (PyMethodDef *)module->ob_ptr;
    for (i = 0; i < module->ob_size; i++) {
        if (strcmp(methods[i].ml_name, name) == 0) return methods[i].ml_meth;
    }
    return 0;
}

static void copy_cstr(const char *src, char *dst, int cap) {
    int i;
    i = 0;
    while (src[i] != 0 && i < cap - 1) { dst[i] = src[i]; i = i + 1; }
    dst[i] = 0;
}

long container_ext_sum_range(int n) {
    PyObject *module;
    PyCFunction fn;
    PyObject *args;
    PyObject *result;
    long rv;

    module = PyInit_container_ext();
    fn = find_method(module, "sum_range");
    args = PyTuple_New(1);
    PyTuple_SetItem(args, 0, PyLong_FromLong((long)n));
    result = (fn != 0) ? fn(0, args) : 0;
    rv = (result != 0) ? PyLong_AsLong(result) : -1;
    Py_XDECREF(args);
    Py_XDECREF(result);
    Py_XDECREF(module);
    return rv;
}

int container_ext_join_lengths(const char *csv, char *outbuf, int outcap) {
    PyObject *module;
    PyCFunction fn;
    PyObject *args;
    PyObject *result;
    const char *s;
    int ok;

    module = PyInit_container_ext();
    fn = find_method(module, "join_lengths");
    args = PyTuple_New(1);
    PyTuple_SetItem(args, 0, PyUnicode_FromString(csv));
    result = (fn != 0) ? fn(0, args) : 0;
    ok = 0;
    outbuf[0] = 0;
    if (result != 0) {
        s = PyUnicode_AsUTF8(result);
        if (s != 0) { copy_cstr(s, outbuf, outcap); ok = 1; }
    }
    Py_XDECREF(args);
    Py_XDECREF(result);
    Py_XDECREF(module);
    return ok;
}

int container_ext_char_histogram(const char *s, char *outbuf, int outcap) {
    PyObject *module;
    PyCFunction fn;
    PyObject *args;
    PyObject *result;
    const char *rs;
    int ok;

    module = PyInit_container_ext();
    fn = find_method(module, "char_histogram");
    args = PyTuple_New(1);
    PyTuple_SetItem(args, 0, PyUnicode_FromString(s));
    result = (fn != 0) ? fn(0, args) : 0;
    ok = 0;
    outbuf[0] = 0;
    if (result != 0) {
        rs = PyUnicode_AsUTF8(result);
        if (rs != 0) { copy_cstr(rs, outbuf, outcap); ok = 1; }
    }
    Py_XDECREF(args);
    Py_XDECREF(result);
    Py_XDECREF(module);
    return ok;
}

int container_ext_bytes_roundtrip(const char *data, int datalen, char *outbuf, int outcap) {
    PyObject *module;
    PyCFunction fn;
    PyObject *args;
    PyObject *result;
    const char *rs;
    int ok;

    module = PyInit_container_ext();
    fn = find_method(module, "bytes_roundtrip");
    args = PyTuple_New(1);
    PyTuple_SetItem(args, 0, PyBytes_FromStringAndSize(data, (Py_ssize_t)datalen));
    result = (fn != 0) ? fn(0, args) : 0;
    ok = 0;
    outbuf[0] = 0;
    if (result != 0) {
        rs = PyUnicode_AsUTF8(result);
        if (rs != 0) { copy_cstr(rs, outbuf, outcap); ok = 1; }
    }
    Py_XDECREF(args);
    Py_XDECREF(result);
    Py_XDECREF(module);
    return ok;
}
