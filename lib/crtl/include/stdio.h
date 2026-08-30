/* SPDX-License-Identifier: Zlib */
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

#define BUFSIZ 8192
#define _IOFBF 0
#define _IOLBF 1
#define _IONBF 2
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define FILENAME_MAX 4096
#define L_tmpnam 20

#include <stdarg.h>

int printf(const char *fmt, ...);
int fprintf(FILE *stream, const char *fmt, ...);
int sprintf(char *s, const char *fmt, ...);
int snprintf(char *s, size_t n, const char *fmt, ...);
int vprintf(const char *fmt, va_list ap);
int vfprintf(FILE *stream, const char *fmt, va_list ap);
int vsprintf(char *s, const char *fmt, va_list ap);

/* asprintf/vasprintf — GNU, not C99. Allocate an exact-fit buffer with malloc
   and hand ownership to the caller; on failure *strp is NULL and the return is
   -1, which is glibc's behaviour and what callers in the wild rely on. */
int asprintf(char **strp, const char *fmt, ...);
int vasprintf(char **strp, const char *fmt, va_list ap);
int vsnprintf(char *s, size_t n, const char *fmt, va_list ap);
int sscanf(const char *s, const char *fmt, ...);
int vsscanf(const char *s, const char *fmt, va_list ap);
int puts(const char *s);
int fputs(const char *s, FILE *stream);
void perror(const char *msg);
int putchar(int c);
int fputc(int c, FILE *stream);
int putc(int c, FILE *stream);
int fgetc(FILE *stream);
int getc(FILE *stream);
int getchar(void);
int ungetc(int c, FILE *stream);
char *fgets(char *s, int n, FILE *stream);
FILE *fopen(const char *path, const char *mode);
FILE *fdopen(int fd, const char *mode);
int fileno(FILE *stream);
FILE *freopen(const char *path, const char *mode, FILE *stream);
FILE *tmpfile(void);
char *tmpnam(char *s);
int fclose(FILE *stream);
int fflush(FILE *stream);
size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);
int fseek(FILE *stream, long off, int whence);
long ftell(FILE *stream);
void rewind(FILE *stream);
int feof(FILE *stream);
int ferror(FILE *stream);
void clearerr(FILE *stream);
int setvbuf(FILE *stream, char *buf, int mode, size_t size);
void setbuf(FILE *stream, char *buf);
int remove(const char *path);
int rename(const char *oldp, const char *newp);

/* The _unlocked family — aliases of the plain spellings, since crtl's FILE has
   no lock to skip. Declared because real code (busybox's libbb) calls them by
   name for speed; see the note in the sibling stdio.c. */
int    fileno_unlocked(FILE *stream);
int    ferror_unlocked(FILE *stream);
int    feof_unlocked(FILE *stream);
void   clearerr_unlocked(FILE *stream);
int    fflush_unlocked(FILE *stream);
int    fputs_unlocked(const char *s, FILE *stream);
int    fputc_unlocked(int c, FILE *stream);
int    putc_unlocked(int c, FILE *stream);
int    putchar_unlocked(int c);
int    fgetc_unlocked(FILE *stream);
int    getc_unlocked(FILE *stream);
int    getchar_unlocked(void);
char  *fgets_unlocked(char *s, int n, FILE *stream);
size_t fread_unlocked(void *ptr, size_t size, size_t nmemb, FILE *stream);
size_t fwrite_unlocked(const void *ptr, size_t size, size_t nmemb, FILE *stream);
void   flockfile(FILE *stream);
void   funlockfile(FILE *stream);
int    ftrylockfile(FILE *stream);

#endif
