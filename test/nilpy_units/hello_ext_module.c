/* M1 "hello-ext" milestone (feature-nilpy-cpyext-c-api-from-source): a
 * hand-written CPython C extension module, in the ordinary shape a real
 * extension takes (PyMethodDef table, PyModuleDef, PyInit_<name>), compiled
 * by cfront against pxx's own lib/cpyext/include/Python.h. This file itself
 * is nothing but the module: no pxx-specific glue lives here — that is
 * test/nilpy_units/hello_ext_host.c, which stands in for what an embedder
 * (or a real CPython interpreter's import machinery) would do with it. */

#include <Python.h>

static PyObject *
hello_add_one(PyObject *self, PyObject *args)
{
    int x;

    if (!PyArg_ParseTuple(args, "i", &x))
        return NULL;
    return PyLong_FromLong((long)(x + 1));
}

static PyMethodDef HelloMethods[] = {
    {"add_one", hello_add_one, METH_VARARGS, "Add one to an integer."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef hellomodule = {
    PyModuleDef_HEAD_INIT,
    "hello_ext",
    NULL,
    -1,
    HelloMethods
};

PyMODINIT_FUNC
PyInit_hello_ext(void)
{
    return PyModule_Create(&hellomodule);
}
