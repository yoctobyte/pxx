/* M4 "a real extension" driver: same embedding shape as hello_ext_host.c /
 * argerr_ext_host.c / container_ext_host.c, but for a vendored, unmodified
 * real PyPI extension (test/nilpy_units/vendor/_speedups.c).
 * Discovers PyInit__speedups (the module's real PyInit_<name> symbol — its
 * "as if pip-installed" name is markupsafe._speedups, unrelated to this
 * file's own name), calls its single method "_escape_inner" under the real
 * METH_O convention: the arg is passed DIRECTLY as the second parameter, not
 * wrapped in a tuple (matches the uniform PyCFunction(self, arg) shape this
 * runtime already uses for every calling convention). */

#include <Python.h>
#include <string.h>

extern PyObject *PyInit__speedups(void);

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

int markupsafe_ext_escape(const char *s, char *outbuf, int outcap) {
    PyObject *module;
    PyCFunction fn;
    PyObject *arg;
    PyObject *result;
    const char *rs;
    int ok;

    module = PyInit__speedups();
    fn = find_method(module, "_escape_inner");
    arg = PyUnicode_FromString(s);
    /* METH_O: pass arg directly as the "args" parameter, no tuple. */
    result = (fn != 0) ? fn(0, arg) : 0;
    ok = 0;
    outbuf[0] = 0;
    if (result != 0) {
        rs = PyUnicode_AsUTF8(result);
        if (rs != 0) { copy_cstr(rs, outbuf, outcap); ok = 1; }
    }
    Py_XDECREF(arg);
    Py_XDECREF(result);
    Py_XDECREF(module);
    return ok;
}
