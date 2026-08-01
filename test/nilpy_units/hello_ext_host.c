/* M1 "hello-ext" driver: the embedding-side glue a NilPy `import` uses to
 * reach a compiled CPython extension. Discovers PyInit_hello_ext (the
 * PyInit_<name> convention every extension module follows), gets back the
 * module object PyModule_Create built from the real PyModuleDef/PyMethodDef
 * table in hello_ext_module.c, looks up "add_one" by name the way a real import
 * system walks ml_methods, and calls it under the real CPython calling
 * convention: PyCFunction(self, args-tuple) -> PyObject*.
 *
 * A later milestone should replace the single fixed-shape entry point below
 * with a generic method dispatcher once PyArg_ParseTuple/Py_BuildValue cover
 * more formats (M2) — for M1 the goal is proving the header, the module
 * table, and the import binding end to end, not a generic FFI. */

#include <Python.h>
#include <string.h>

extern PyObject *PyInit_hello_ext(void);

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

int hello_ext_add_one(int x) {
    PyObject *module;
    PyCFunction fn;
    PyObject *args;
    PyObject *result;
    int rv;

    module = PyInit_hello_ext();
    fn = find_method(module, "add_one");
    if (fn == 0) {
        Py_XDECREF(module);
        return -1;
    }
    args = PyTuple_New(1);
    PyTuple_SetItem(args, 0, PyLong_FromLong((long)x));
    result = fn(0, args);
    rv = (result != 0) ? (int)PyLong_AsLong(result) : -1;
    Py_XDECREF(args);
    Py_XDECREF(result);
    Py_XDECREF(module);
    return rv;
}
