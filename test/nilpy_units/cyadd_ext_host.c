/* cpyext M5a driver: reach a CYTHON-generated module's functions.
 *
 * The M1-M4 drivers walk the module's static PyMethodDef table. That does not
 * work here and the difference is the milestone: Cython 3 emits an EMPTY
 * m_methods and registers its module-level `def`s into the module DICT from a
 * Py_mod_exec slot. So this driver goes through the same door a real import
 * would — PyInit_<name> -> PEP 489 create+exec (pyruntime.c runs the slots)
 * -> getattr on the module -> PyObject_Call.
 *
 * The module is built ONCE and cached: Cython's own create slot returns the
 * existing module on a second call, and rebuilding per call would leak.
 */

#include <Python.h>

extern PyObject *PyInit_cyadd(void);

static PyObject *g_cyadd_module = 0;

static PyObject *cyadd_module(void) {
    if (g_cyadd_module == 0) g_cyadd_module = PyInit_cyadd();
    return g_cyadd_module;
}

/* One int argument in, one out — enough for both functions this module has.
   Returns -1 with the error left pending on any failure; the NilPy side turns
   a pending error into an exception, so a silent -1 cannot be mistaken for a
   result. */
static long cyadd_call(const char *name, long a, long b, int nargs) {
    PyObject *module;
    PyObject *fn;
    PyObject *args;
    PyObject *result;
    long rv;

    module = cyadd_module();
    if (module == 0) return -1;
    fn = PyObject_GetAttrString(module, name);
    if (fn == 0) return -1;
    args = PyTuple_New(nargs);
    PyTuple_SetItem(args, 0, PyLong_FromLong(a));
    if (nargs > 1) PyTuple_SetItem(args, 1, PyLong_FromLong(b));
    result = PyObject_Call(fn, args, 0);
    rv = (result != 0) ? PyLong_AsLong(result) : -1;
    Py_XDECREF(result);
    Py_XDECREF(args);
    Py_XDECREF(fn);
    return rv;
}

int cyadd_ext_add(int a, int b) {
    return (int)cyadd_call("cyadd", (long)a, (long)b, 2);
}

int cyadd_ext_fact(int n) {
    return (int)cyadd_call("cyfact", (long)n, 0, 1);
}
