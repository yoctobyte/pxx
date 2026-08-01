/* M2 "arguments and errors" driver: the embedding-side glue a NilPy `import`
 * uses to reach argerr_ext_module.c. Same shape as hello_ext_host.c (M1):
 * discover PyInit_argerr_ext, walk its PyMethodDef table, call under the
 * real PyCFunction(self, args) convention — widened to the format letters
 * and error path M2 adds. Every entry point here uses only plain C scalar
 * types and `char *` buffers on the Pascal-facing boundary (proven safe via
 * pxxcio's own `PChar` parameters), never a raw `int*`/`long*` out-param —
 * an error is reported through an errbuf string instead, kept simple for
 * this milestone's driver rather than a generic reflector (same scope note
 * as hello_ext_host.c). */

#include <Python.h>
#include <string.h>

extern PyObject *PyInit_argerr_ext(void);

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

double argerr_ext_scale(int x, double factor) {
    PyObject *module;
    PyCFunction fn;
    PyObject *args;
    PyObject *result;
    double rv;

    module = PyInit_argerr_ext();
    fn = find_method(module, "scale");
    args = PyTuple_New(2);
    PyTuple_SetItem(args, 0, PyLong_FromLong((long)x));
    PyTuple_SetItem(args, 1, PyFloat_FromDouble(factor));
    result = (fn != 0) ? fn(0, args) : 0;
    rv = (result != 0) ? PyFloat_AsDouble(result) : -1.0;
    Py_XDECREF(args);
    Py_XDECREF(result);
    Py_XDECREF(module);
    return rv;
}

int argerr_ext_shout(const char *word, char *outbuf, int outcap) {
    PyObject *module;
    PyCFunction fn;
    PyObject *args;
    PyObject *result;
    const char *s;
    int ok;

    module = PyInit_argerr_ext();
    fn = find_method(module, "shout");
    args = PyTuple_New(1);
    PyTuple_SetItem(args, 0, PyUnicode_FromString(word));
    result = (fn != 0) ? fn(0, args) : 0;
    ok = 0;
    outbuf[0] = 0;
    if (result != 0) {
        s = PyUnicode_AsUTF8(result);
        if (s != 0) {
            copy_cstr(s, outbuf, outcap);
            ok = 1;
        }
    }
    Py_XDECREF(args);
    Py_XDECREF(result);
    Py_XDECREF(module);
    return ok;
}

int argerr_ext_prefix_len(const char *data, int datalen) {
    PyObject *module;
    PyCFunction fn;
    PyObject *args;
    PyObject *result;
    int rv;

    module = PyInit_argerr_ext();
    fn = find_method(module, "prefix_len");
    args = PyTuple_New(1);
    PyTuple_SetItem(args, 0, PyUnicode_FromStringAndSize(data, (Py_ssize_t)datalen));
    result = (fn != 0) ? fn(0, args) : 0;
    rv = (result != 0) ? (int)PyLong_AsLong(result) : -1;
    Py_XDECREF(args);
    Py_XDECREF(result);
    Py_XDECREF(module);
    return rv;
}

int argerr_ext_identity(int x) {
    PyObject *module;
    PyCFunction fn;
    PyObject *args;
    PyObject *result;
    int rv;

    module = PyInit_argerr_ext();
    fn = find_method(module, "identity");
    args = PyTuple_New(1);
    PyTuple_SetItem(args, 0, PyLong_FromLong((long)x));
    result = (fn != 0) ? fn(0, args) : 0;
    rv = (result != 0) ? (int)PyLong_AsLong(result) : -1;
    Py_XDECREF(args);
    Py_XDECREF(result);
    Py_XDECREF(module);
    return rv;
}

/* Returns the checked value on success. On failure returns -1 AND fills
 * errbuf with the extension's PyErr_SetString message (cleared afterwards);
 * the Pascal caller distinguishes the two by errbuf[0], not by the return
 * value, since -1 is also a value check_positive could legitimately reject
 * (though never accept). */
int argerr_ext_check_positive(int x, char *errbuf, int errcap) {
    PyObject *module;
    PyCFunction fn;
    PyObject *args;
    PyObject *result;
    int rv;

    module = PyInit_argerr_ext();
    fn = find_method(module, "check_positive");
    args = PyTuple_New(1);
    PyTuple_SetItem(args, 0, PyLong_FromLong((long)x));
    result = (fn != 0) ? fn(0, args) : 0;
    errbuf[0] = 0;
    if (result != 0) {
        rv = (int)PyLong_AsLong(result);
    } else {
        copy_cstr(__pxx_PyErr_Message(), errbuf, errcap);
        PyErr_Clear();
        rv = -1;
    }
    Py_XDECREF(args);
    Py_XDECREF(result);
    Py_XDECREF(module);
    return rv;
}
