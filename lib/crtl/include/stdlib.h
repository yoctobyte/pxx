#ifndef PXX_CRTL_STDLIB_H
#define PXX_CRTL_STDLIB_H 1

#include <stddef.h>

#ifndef NULL
#define NULL 0
#endif

void *malloc(size_t size);
void *calloc(size_t count, size_t size);
void *realloc(void *ptr, size_t size);
void free(void *ptr);

int atoi(const char *s);
long atol(const char *s);
long long atoll(const char *s);

void abort(void);
void exit(int status);

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1

#endif
