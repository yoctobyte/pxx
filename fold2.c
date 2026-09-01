struct T { int x; int y; };
extern struct T ta[];        /* array of structs */
extern int m2[];             /* plain int array */
extern struct T single;
int g_arrfield(void) { return ta[4].y; }   /* +4*8+4 = 36 if folded */
int g_arrfield0(void){ return ta[0].x; }
int g_var(int i)     { return m2[i]; }     /* variable index */
int g_big(void)      { return m2[1000]; }  /* +4000 if folded */
int g_sfield(void)   { return single.y; }  /* +4 if folded */
