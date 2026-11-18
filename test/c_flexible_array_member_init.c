/* An initialised flexible array member keeps its elements, and the object
   grows to hold them (NetBSD ioconf.c cfiattrdata tables).
   bug-c-an-initialised-flexible-array-member-is-dropped */
#include <stdio.h>
struct ia { int n; int v[]; };
struct pa { int n; const char *v[]; };
struct sa { int n; struct { const char *s; int k; } v[]; };
static const struct ia I = { 2, { 7, 8 } };
static const struct pa P = { 2, { "a", "b" } };
struct cflocdesc { const char *cld_name; const char *cld_defaultstr; int cld_default; };
struct cfiattrdata { const char *ci_name; int ci_loclen; const struct cflocdesc ci_locdesc[]; };
static const struct cfiattrdata pcicf = { "pci", 2, { { "dev", "-1", -1 }, { "function", "-1", -2 }, } };
static const struct cfiattrdata busf = { "pcibus", 1, { { "bus", "-1", -1 }, } };
static const struct sa A = { 2, { { "x", 1 }, { "y", 2 } } };
static struct sa B = { 1, { { "z", 3 } } };
int after = 99;
int main(void) {
    printf("%d %d\n", pcicf.ci_locdesc[1].cld_default, busf.ci_locdesc[0].cld_name[0]);
    printf("sizeof %zu %zu %zu\n", sizeof I, sizeof P, sizeof A);
    printf("I %d %d\n", I.v[0], I.v[1]);
    printf("P %s %s\n", P.v[0] ? P.v[0] : "-", P.v[1] ? P.v[1] : "-");
    printf("A %s %d %s %d\n", A.v[0].s ? A.v[0].s : "-", A.v[0].k, A.v[1].s ? A.v[1].s : "-", A.v[1].k);
    printf("B %s %d after %d\n", B.v[0].s ? B.v[0].s : "-", B.v[0].k, after);
    return 0;
}
