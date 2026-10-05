typedef struct { unsigned int a : 1; unsigned int b : 1; unsigned int c : 4; unsigned int d : 10; } flags_t;
typedef union { struct { unsigned short d0 : 15; unsigned short l0 : 1; unsigned short d1 : 15; unsigned short l1 : 1; }; unsigned int val; } sym_t;
static inline unsigned int c_flags_word(void) { flags_t f = {0}; f.b = 1; f.c = 5; f.d = 700; return *(unsigned int *)&f; }
