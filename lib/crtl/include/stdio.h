#ifndef PXX_CRTL_STDIO_H
#define PXX_CRTL_STDIO_H 1

#include <stddef.h>

#ifndef NULL
#define NULL 0
#endif

#define EOF (-1)

typedef struct PxxCrtlFile FILE;

extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;

int printf(const char *fmt);
int puts(const char *s);
int fputs(const char *s, FILE *stream);
int putchar(int c);

#endif
