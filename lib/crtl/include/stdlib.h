/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_STDLIB_H
#define PXX_CRTL_STDLIB_H 1

#include <stddef.h>

#ifndef NULL
#define NULL 0
#endif

void *malloc(size_t size);
void *calloc(size_t count, size_t size);
void *realloc(void *ptr, size_t size);
void *reallocarray(void *ptr, size_t nmemb, size_t size);
void free(void *ptr);

int atoi(const char *s);
long atol(const char *s);
long long atoll(const char *s);
double atof(const char *s);
double strtod(const char *s, char **end);
long strtol(const char *s, char **end, int base);
unsigned long strtoul(const char *s, char **end, int base);
long long strtoll(const char *s, char **end, int base);
unsigned long long strtoull(const char *s, char **end, int base);

int abs(int n);
long labs(long n);

int rand(void);
void srand(unsigned int seed);

char *getenv(const char *name);
int system(const char *command);

void qsort(void *base, size_t nmemb, size_t size, int (*cmp)(const void *, const void *));
void *bsearch(const void *key, void *base, size_t nmemb, size_t size, int (*cmp)(const void *, const void *));

void abort(void);
void exit(int status);
void _Exit(int status);
int atexit(void (*func)(void));

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1

#define MB_CUR_MAX 1

#endif
