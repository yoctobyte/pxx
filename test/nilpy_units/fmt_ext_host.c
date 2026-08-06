/* cpyext: PyErr_Format's printf SUPERSET, exercised specifier by specifier.
 *
 * CPython's PyErr_Format / PyUnicode_FromFormat accept %U (a PyObject* str),
 * %S (str() of anything), %R (repr()), %A (ascii()) on top of printf. This
 * runtime delegated to vsnprintf, which knows none of them: it printed them
 * literally AND consumed no argument, so anything after one read the wrong
 * va_arg. bug-cpyext-pyerr-format-prints-U-and-S-literally
 *
 * Every expected string is what the SAME PyErr_Format calls produce under real
 * CPython 3.12, captured from a gcc-built extension (see the test's header).
 */

#include <Python.h>

/* pyruntime.c's accessor for the pending error's text — the limited API has no
 * way to read a message without building an exception object. */
extern const char *__pxx_PyErr_Message(void);

static void take(char *out, int cap) {
    const char *m;
    int i;

    m = __pxx_PyErr_Message();
    i = 0;
    while (m[i] != 0 && i < cap - 1) { out[i] = m[i]; i++; }
    if (cap > 0) out[i] = 0;
    PyErr_Clear();
}

/* One case per call so the Pascal side can print them in order. Returns 0 on a
 * recognised case, -1 otherwise. */
int fmt_ext_case(int which, char *out, int cap) {
    PyObject *u;
    PyObject *n;
    int rv;

    if (cap > 0) out[0] = 0;
    u = PyUnicode_FromString("keyname");
    n = PyLong_FromLong(1234);
    rv = 0;
    PyErr_Clear();

    switch (which) {
        case 0: PyErr_Format(PyExc_TypeError, "U=[%U]", u); break;
        case 1: PyErr_Format(PyExc_TypeError, "S=[%S]", n); break;
        case 2: PyErr_Format(PyExc_TypeError, "R=[%R]", u); break;
        case 3: PyErr_Format(PyExc_TypeError, "A=[%A]", u); break;
        /* the misalignment case: with %U consuming nothing, the %d after it read
           the PyObject* and printed a garbage number */
        case 4: PyErr_Format(PyExc_TypeError, "mix=[%U][%d]", u, 77); break;
        case 5: PyErr_Format(PyExc_TypeError, "s=[%s] d=[%d]", "txt", -5); break;
        /* length modifiers: reading an int for a %ld would misalign the rest */
        case 6: PyErr_Format(PyExc_TypeError, "ld=[%ld] zd=[%zd]",
                             (long)9876543210L, (Py_ssize_t)42); break;
        case 7: PyErr_Format(PyExc_TypeError, "pct=[100%%] c=[%c]", 'Z'); break;
        case 8: PyErr_Format(PyExc_TypeError, "x=[%x] wide=[%5d]", 255, 7); break;
        default: rv = -1; break;
    }

    if (rv == 0) take(out, cap);
    Py_XDECREF(n);
    Py_XDECREF(u);
    return rv;
}

/* PyUnicode_FromFormat takes the SAME superset in CPython and had the identical
 * bug, so it gets a case too — read back as a plain string, not via the error
 * state. */
int fmt_ext_unicode(char *out, int cap) {
    PyObject *u;
    PyObject *r;
    const char *s;
    int i;

    if (cap > 0) out[0] = 0;
    u = PyUnicode_FromString("keyname");
    r = PyUnicode_FromFormat("fmt=[%U][%d]", u, 5);
    s = (r != 0) ? PyUnicode_AsUTF8(r) : 0;
    if (s == 0) s = "";
    i = 0;
    while (s[i] != 0 && i < cap - 1) { out[i] = s[i]; i++; }
    if (cap > 0) out[i] = 0;
    Py_XDECREF(r);
    Py_XDECREF(u);
    return 0;
}
