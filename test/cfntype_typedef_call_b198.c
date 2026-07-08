/* b198: function-TYPE typedef `typedef R N(args);` used as `N *p` (and `N p`)
   must be callable through the pointer (bug-c-inline-fnptr-param-call). stb's
   STBSP_SPRINTFCB idiom. Previously "call to undeclared function: cb". */

typedef int CB(int);                         /* function type, no pointer */
typedef char *STRFN(const char *, int);      /* stb-shaped: ptr return, 2 args */

int apply(CB *cb, int x) { return cb(x); }
int twice(CB *cb, int x) { return cb(cb(x)); }
int inc(int v) { return v + 1; }

char *pick(STRFN *f, const char *s, int n) { return f(s, n); }
char *tail(const char *s, int n) { return (char *)s + n; }

int main(void) {
    if (apply(inc, 41) != 42) return 1;
    if (twice(inc, 40) != 42) return 2;
    { const char *s = "abcdef"; if (pick(tail, s, 4)[0] != 'e') return 3; }
    return 42;
}
