#ifndef PXX_CRTL_SETJMP_H
#define PXX_CRTL_SETJMP_H 1

typedef long jmp_buf;

int setjmp(jmp_buf env);
void longjmp(jmp_buf env, int value);

#endif
