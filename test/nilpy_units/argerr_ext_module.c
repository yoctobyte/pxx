/* M2 "arguments and errors" milestone (feature-nilpy-cpyext-c-api-from-source):
 * a hand-written CPython extension exercising PyArg_ParseTuple/Py_BuildValue
 * across the common format letters ("i l d s s# O") and PyErr_SetString error
 * propagation, in the ordinary shape a real extension takes. Compiled by
 * cfront against lib/cpyext/include/Python.h. Not named argerr_ext.c on
 * purpose — see the comment atop argerr_ext.pas
 * (bug-c-uses-path-basename-collides-with-enclosing-unit-name). */

#include <Python.h>

/* "l" (long) + "d" (double) in, "d" out. */
static PyObject *
argerr_scale(PyObject *self, PyObject *args)
{
    long x;
    double factor;

    if (!PyArg_ParseTuple(args, "ld", &x, &factor))
        return NULL;
    return Py_BuildValue("d", (double)x * factor);
}

/* "s" (NUL-terminated C string) in, "s" out. */
static PyObject *
argerr_shout(PyObject *self, PyObject *args)
{
    const char *word;
    char buf[256];
    int i;

    if (!PyArg_ParseTuple(args, "s", &word))
        return NULL;
    i = 0;
    while (word[i] != 0 && i < 255) {
        char c = word[i];
        if (c >= 'a' && c <= 'z') c = (char)(c - ('a' - 'A'));
        buf[i] = c;
        i = i + 1;
    }
    buf[i] = 0;
    return Py_BuildValue("s", buf);
}

/* "s#" (pointer + length) in, "i" out: the length CPython handed us. */
static PyObject *
argerr_prefix_len(PyObject *self, PyObject *args)
{
    const char *data;
    Py_ssize_t len;

    if (!PyArg_ParseTuple(args, "s#", &data, &len))
        return NULL;
    return Py_BuildValue("i", (int)len);
}

/* "O" (a raw, unconverted PyObject*) in, same object out. */
static PyObject *
argerr_identity(PyObject *self, PyObject *args)
{
    PyObject *obj;

    if (!PyArg_ParseTuple(args, "O", &obj))
        return NULL;
    Py_INCREF(obj);
    return obj;
}

/* "i" in; raises ValueError via PyErr_SetString for a negative argument
 * instead of returning a value — the M2 error-propagation path. */
static PyObject *
argerr_check_positive(PyObject *self, PyObject *args)
{
    int x;

    if (!PyArg_ParseTuple(args, "i", &x))
        return NULL;
    if (x < 0) {
        PyErr_SetString(PyExc_ValueError, "x must be non-negative");
        return NULL;
    }
    return Py_BuildValue("i", x);
}

static PyMethodDef ArgErrMethods[] = {
    {"scale", argerr_scale, METH_VARARGS, "Multiply an int by a float."},
    {"shout", argerr_shout, METH_VARARGS, "Uppercase a string."},
    {"prefix_len", argerr_prefix_len, METH_VARARGS, "Length CPython measured via s#."},
    {"identity", argerr_identity, METH_VARARGS, "Return the argument unchanged."},
    {"check_positive", argerr_check_positive, METH_VARARGS, "Raise ValueError if negative."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef argerrmodule = {
    PyModuleDef_HEAD_INIT,
    "argerr_ext",
    NULL,
    -1,
    ArgErrMethods
};

PyMODINIT_FUNC
PyInit_argerr_ext(void)
{
    return PyModule_Create(&argerrmodule);
}
