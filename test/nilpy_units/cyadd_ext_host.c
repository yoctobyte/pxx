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

/* pyruntime.c's own accessor for the pending error's text — the limited API has
   no way to read a message without building an exception object, and this driver
   only needs the string to hand to the Pascal side. */
extern const char *__pxx_PyErr_Message(void);

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

/* --- M5b: keyword arguments through the vectorcall path -------------------
 *
 * The calls above pass kwargs = 0. Cython's generated functions are
 * METH_FASTCALL|METH_KEYWORDS, and the vectorcall layout puts the keyword
 * VALUES in the same array after the positional ones with a `kwnames` tuple
 * carrying the matching names. pyruntime.c used to refuse keywords here
 * outright; these entry points are what exercise the wiring.
 *
 * cysub is deliberately the function under test rather than cyadd: addition is
 * commutative, so a kwnames tuple whose order did not match the values it
 * describes would still produce the right sum and the bug would be invisible.
 * `cysub(b=8, a=30)` is 22 under CPython and -22 if the pairing is swapped.
 */
static long cyadd_call_kw(const char *name, long pos0, int npos,
                          const char *k1, long v1,
                          const char *k2, long v2) {
    PyObject *module;
    PyObject *fn;
    PyObject *args;
    PyObject *kw;
    PyObject *result;
    PyObject *nameobj;
    long rv;

    module = cyadd_module();
    if (module == 0) return -1;
    fn = PyObject_GetAttrString(module, name);
    if (fn == 0) return -1;

    args = PyTuple_New(npos);
    if (npos > 0) PyTuple_SetItem(args, 0, PyLong_FromLong(pos0));

    kw = PyDict_New();
    /* insertion order is the order the names tuple will be built in */
    if (k1 != 0) {
        nameobj = PyUnicode_FromString(k1);
        PyDict_SetItem(kw, nameobj, PyLong_FromLong(v1));
        Py_DECREF(nameobj);
    }
    if (k2 != 0) {
        nameobj = PyUnicode_FromString(k2);
        PyDict_SetItem(kw, nameobj, PyLong_FromLong(v2));
        Py_DECREF(nameobj);
    }

    result = PyObject_Call(fn, args, kw);
    rv = (result != 0) ? PyLong_AsLong(result) : -1;
    Py_XDECREF(result);
    Py_XDECREF(kw);
    Py_XDECREF(args);
    Py_XDECREF(fn);
    return rv;
}

int cyadd_ext_sub(int a, int b) {
    return (int)cyadd_call("cysub", (long)a, (long)b, 2);
}

/* cysub(a=a, b=b) — every argument by keyword, none positional */
int cyadd_ext_sub_kw(int a, int b) {
    return (int)cyadd_call_kw("cysub", 0, 0, "a", (long)a, "b", (long)b);
}

/* cysub(b=b, a=a) — the SAME call with the keywords inserted in the opposite
   order, which must still answer a - b */
int cyadd_ext_sub_kw_rev(int a, int b) {
    return (int)cyadd_call_kw("cysub", 0, 0, "b", (long)b, "a", (long)a);
}

/* cysub(a, b=b) — positional and keyword in one call, the layout where nargs
   and the array length genuinely differ */
int cyadd_ext_sub_mixed(int a, int b) {
    return (int)cyadd_call_kw("cysub", (long)a, 1, "b", (long)b, 0, 0);
}

/* an UNKNOWN keyword must reach Cython's own parser and raise TypeError, not be
   silently dropped — the failure mode a hand-rolled kwnames invites. The message
   is copied out for the Pascal side to raise, the same way argerr_ext does it:
   returning -1 alone would be indistinguishable from a result. */
int cyadd_ext_sub_badkw(int a, char *errbuf, int errcap) {
    long rv;
    const char *msg;
    int i;

    if (errcap > 0) errbuf[0] = 0;
    PyErr_Clear();
    rv = cyadd_call_kw("cysub", (long)a, 1, "c", 1, 0, 0);
    if (PyErr_Occurred() != 0) {
        msg = __pxx_PyErr_Message();
        i = 0;
        while (msg[i] != 0 && i < errcap - 1) { errbuf[i] = msg[i]; i++; }
        if (errcap > 0) errbuf[i] = 0;
        PyErr_Clear();
    }
    return (int)rv;
}

/* --- M5b: PyObject_CallFunctionObjArgs -----------------------------------
 * The NULL-terminated variadic form, which used to be a hard stop. Same call as
 * cyadd_ext_add, reached the other way. */
int cyadd_ext_add_objargs(int a, int b) {
    PyObject *module;
    PyObject *fn;
    PyObject *pa;
    PyObject *pb;
    PyObject *result;
    long rv;

    module = cyadd_module();
    if (module == 0) return -1;
    fn = PyObject_GetAttrString(module, "cyadd");
    if (fn == 0) return -1;
    pa = PyLong_FromLong((long)a);
    pb = PyLong_FromLong((long)b);
    result = PyObject_CallFunctionObjArgs(fn, pa, pb, (PyObject *)0);
    rv = (result != 0) ? PyLong_AsLong(result) : -1;
    Py_XDECREF(result);
    Py_DECREF(pb);
    Py_DECREF(pa);
    Py_DECREF(fn);
    return (int)rv;
}

/* --- M5b: the CyFunction heap type, made observable ------------------------
 *
 * Everything above would produce the same numbers whether the module was
 * generated with `-X binding=False` (module-level defs are plain builtin
 * functions) or without it (they are instances of Cython's own CyFunction heap
 * type). Dropping that flag is the whole milestone, so the test has to be able
 * to TELL, and only introspection can tell:
 *
 *   type name  — `cython_function_or_method`, a heap type built from a
 *                PyType_Spec through PyType_FromMetaclass, versus a plain
 *                builtin function object
 *   __name__ / __qualname__ — served by the type's Py_tp_getset table
 *   __code__.co_varnames    — a code object, built by CALLING types.CodeType
 *                             because the limited API hides PyCode_New
 *
 * Each answer is compared against the same generated C running under real
 * CPython 3.12; see the .npy test for the recipe.
 *
 * The buffer contract is the one argerr_ext already uses: copy out, NUL
 * terminate, empty string on failure with the error left for the caller.
 */
static void cyadd_copy_str(PyObject *s, char *buf, int cap) {
    const char *p;
    int i;

    if (cap <= 0) return;
    buf[0] = 0;
    if (s == 0 || !PyUnicode_Check(s)) return;
    p = PyUnicode_AsUTF8(s);
    i = 0;
    while (p[i] != 0 && i < cap - 1) { buf[i] = p[i]; i++; }
    buf[i] = 0;
}

static PyObject *cyadd_fn(const char *name) {
    PyObject *module;
    module = cyadd_module();
    if (module == 0) return 0;
    return PyObject_GetAttrString(module, name);
}

/* The type's name as its spec declared it. Cython builds it dotted
   (`<abi module>.cython_function_or_method`); CPython reports the last
   component as the type's __name__, so the last component is what is
   compared. */
void cyadd_ext_fn_typename(const char *name, char *buf, int cap) {
    PyObject *fn;
    const char *tn;
    const char *last;
    int i;

    if (cap > 0) buf[0] = 0;
    fn = cyadd_fn(name);
    if (fn == 0) return;
    tn = Py_TYPE(fn)->tp_name;
    last = tn;
    i = 0;
    while (tn[i] != 0) { if (tn[i] == '.') last = tn + i + 1; i++; }
    i = 0;
    while (last[i] != 0 && i < cap - 1) { buf[i] = last[i]; i++; }
    if (cap > 0) buf[i] = 0;
    Py_DECREF(fn);
}

/* A getset descriptor on the heap type: __name__ or __qualname__. */
void cyadd_ext_fn_attr(const char *name, const char *attr, char *buf, int cap) {
    PyObject *fn;
    PyObject *v;

    if (cap > 0) buf[0] = 0;
    fn = cyadd_fn(name);
    if (fn == 0) return;
    v = PyObject_GetAttrString(fn, attr);
    cyadd_copy_str(v, buf, cap);
    Py_XDECREF(v);
    Py_DECREF(fn);
}

/* __code__.co_varnames, comma-joined. Reaches the code object built through
   types.CodeType and reads a tuple back out of it. */
void cyadd_ext_fn_varnames(const char *name, char *buf, int cap) {
    PyObject *fn;
    PyObject *code;
    PyObject *vn;
    PyObject *item;
    const char *p;
    Py_ssize_t i;
    Py_ssize_t n;
    int o;
    int j;

    if (cap > 0) buf[0] = 0;
    fn = cyadd_fn(name);
    if (fn == 0) return;
    code = PyObject_GetAttrString(fn, "__code__");
    Py_DECREF(fn);
    if (code == 0) return;
    vn = PyObject_GetAttrString(code, "co_varnames");
    Py_DECREF(code);
    if (vn == 0) return;
    o = 0;
    if (PyTuple_Check(vn)) {
        n = PyTuple_Size(vn);
        for (i = 0; i < n; i++) {
            if (i > 0 && o < cap - 1) buf[o++] = ',';
            item = PyTuple_GetItem(vn, i);   /* borrowed */
            if (item != 0 && PyUnicode_Check(item)) {
                p = PyUnicode_AsUTF8(item);
                j = 0;
                while (p[j] != 0 && o < cap - 1) buf[o++] = p[j++];
            }
        }
    }
    if (cap > 0) buf[o] = 0;
    Py_DECREF(vn);
}
