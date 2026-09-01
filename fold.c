struct S { int a; int b; int c; };
extern struct S st;
extern int ia[];
extern int scal;
int f_field(void)  { return st.c; }      /* field offset 8 */
int f_idx5(void)   { return ia[5]; }     /* element offset 20 */
int f_idx0(void)   { return ia[0]; }
int f_scal(void)   { return scal; }
