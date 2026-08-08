/* structmember.h — cpyext (feature-nilpy-cpyext-c-api-from-source, M5b).
 *
 * Cython includes this UNCONDITIONALLY (its IncludeStructmemberH.proto), even
 * under Py_LIMITED_API where every consumer of what it declares is
 * preprocessed away. So the header has to exist; what it declares only has to
 * be right for the paths that survive.
 *
 * Under the limited API, Cython's FixUpExtensionType walks the Py_tp_members
 * slot ITSELF instead of letting the interpreter do it, reading `name`,
 * `type`, `offset` and `flags` off each entry and turning the dunder ones
 * (__dictoffset__, __weaklistoffset__, __vectorcalloffset__) into type fields.
 * That is the whole live use, and it needs the struct LAYOUT to match what the
 * extension's own initialisers produce — nothing more.
 *
 * The T_* codes are CPython's own values, kept identical because an extension
 * may compare against them. Types we cannot honour are still listed: a member
 * table is data, and a missing code would silently read as 0 (= T_SHORT).
 */
#ifndef Py_STRUCTMEMBER_H
#define Py_STRUCTMEMBER_H

#include <Python.h>

/* PyMemberDef is not in the limited API before 3.12, and Cython's own
   declaration is guarded on the CPython path, so cpyext owns it here. */
#ifndef PXX_HAVE_PyMemberDef
#define PXX_HAVE_PyMemberDef 1
typedef struct PyMemberDef {
    const char *name;
    int type;
    Py_ssize_t offset;
    int flags;
    const char *doc;
} PyMemberDef;
#endif

/* CPython's member type codes, same values. */
#define T_SHORT      0
#define T_INT        1
#define T_LONG       2
#define T_FLOAT      3
#define T_DOUBLE     4
#define T_STRING     5
#define T_OBJECT     6
#define T_CHAR       7
#define T_BYTE       8
#define T_UBYTE      9
#define T_USHORT    10
#define T_UINT      11
#define T_ULONG     12
#define T_STRING_INPLACE 13
#define T_BOOL      14
#define T_OBJECT_EX 16
#define T_LONGLONG  17
#define T_ULONGLONG 18
#define T_PYSSIZET  19
#define T_NONE      20

/* Flags. */
#define READONLY            1
#define Py_READONLY         1
#define READ_RESTRICTED     2
#define PY_WRITE_RESTRICTED 4
#define RESTRICTED          (READ_RESTRICTED | PY_WRITE_RESTRICTED)
#define Py_AUDIT_READ       READ_RESTRICTED

#endif /* Py_STRUCTMEMBER_H */
