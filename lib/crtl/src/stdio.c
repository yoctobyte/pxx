/*
 * C runtime: stdio — printf family + the buffered-stream veneer.
 *
 * Project-owned, libc-free. The number/format engine (__crtl_vformat) is pure
 * computation and depends on nothing but the va_list it is handed, so the
 * buffer-only entry points (vsnprintf/snprintf/sprintf/vsprintf) need no
 * syscall at all. The stream entry points (printf/fprintf/fwrite/fputs/...)
 * funnel every byte through ONE sink, __pxx_write, which is the libc-free
 * fd-write primitive the platform (PAL / Pascal RTL) provides — see
 * track-a-c-stdio-needs-pascal-import-and-data-relocs.
 *
 * STATUS (2026-06-26, feat/cfront): this file is the C-side deliverable. It is
 * correct C but does not yet RUN on the current compiler — three frontend /
 * codegen blockers gate it, each filed:
 *   - va_arg of any non-int type -> "invalid symbol in lea"
 *     (track-c-va-arg-nonint-lea) — blocks every %s/%x/%p/%ld read.
 *   - %f/%e/%g read 0 (bug-c-double-vararg).
 *   - the stdin/stdout/stderr objects + __pxx_write need the Pascal-import /
 *     data-reloc work (track-a-c-stdio-needs-pascal-import-and-data-relocs).
 * Engine logic is written so it is immediately exercisable once those land.
 */

#include <stdarg.h>
#include <stddef.h>

/* libc-free byte sink: write `n` bytes of `buf` to fd. Provided by the platform
   (posix syscall / ESP-IDF) the same way Pascal's RTL IO is. */
extern long __pxx_write(int fd, const void *buf, unsigned long n);
extern long __pxx_read(int fd, void *buf, unsigned long n);

/* ---- FILE + the standard streams ------------------------------------------ */

struct PxxCrtlFile {
  int fd;
  int err;
  int eof;
};
typedef struct PxxCrtlFile FILE;

static FILE __crtl_stdin  = { 0, 0, 0 };
static FILE __crtl_stdout = { 1, 0, 0 };
static FILE __crtl_stderr = { 2, 0, 0 };

FILE *stdin  = &__crtl_stdin;
FILE *stdout = &__crtl_stdout;
FILE *stderr = &__crtl_stderr;

/* ---- format engine -------------------------------------------------------- */

/* Unsigned -> string, MSB-first, into `out`; returns digit count. */
static int __crtl_utoa(char *out, unsigned long v, int base, int upper) {
  char tmp[32];
  int n = 0, i, r;
  char d;
  if (v == 0) {
    tmp[n++] = '0';
  } else {
    while (v) {
      r = (int)(v % (unsigned long)base);
      if (r < 10) d = (char)('0' + r);
      else if (upper) d = (char)('A' + r - 10);
      else d = (char)('a' + r - 10);
      tmp[n++] = d;
      v = v / (unsigned long)base;
    }
  }
  for (i = 0; i < n; i++) out[i] = tmp[n - 1 - i];
  return n;
}

/* Core formatter. Writes into buf[0..cap-1] (always NUL-terminates when cap>0),
   and returns the number of chars that WOULD have been written (C99 snprintf
   semantics), so callers can detect truncation. */
static int __crtl_vformat(char *buf, size_t cap, const char *fmt, va_list ap) {
  size_t o = 0;
  int i = 0;
  char c;

  while (fmt[i]) {
    c = fmt[i++];
    if (c != '%') {
      if (o + 1 < cap) buf[o] = c;
      o++;
      continue;
    }

    /* flags */
    int left = 0, zero = 0, plus = 0, space = 0, alt = 0;
    int flagging = 1;
    while (flagging) {
      switch (fmt[i]) {
        case '-': left = 1; i++; break;
        case '0': zero = 1; i++; break;
        case '+': plus = 1; i++; break;
        case ' ': space = 1; i++; break;
        case '#': alt = 1; i++; break;
        default: flagging = 0; break;
      }
    }

    /* width (number or '*') */
    int width = 0;
    if (fmt[i] == '*') { width = va_arg(ap, int); i++; if (width < 0) { left = 1; width = -width; } }
    else while (fmt[i] >= '0' && fmt[i] <= '9') { width = width * 10 + (fmt[i] - '0'); i++; }

    /* precision (number or '*') */
    int prec = -1;
    if (fmt[i] == '.') {
      i++;
      prec = 0;
      if (fmt[i] == '*') { prec = va_arg(ap, int); i++; if (prec < 0) prec = -1; }
      else while (fmt[i] >= '0' && fmt[i] <= '9') { prec = prec * 10 + (fmt[i] - '0'); i++; }
    }

    /* length modifiers — parsed for source compatibility (all read as long-or-
       smaller through the GP save area on this ABI). */
    int lng = 0;
    while (fmt[i] == 'l' || fmt[i] == 'h' || fmt[i] == 'z' || fmt[i] == 'j' || fmt[i] == 't') {
      if (fmt[i] == 'l') lng++;
      i++;
    }

    char k = fmt[i++];

    char num[32];
    char one[2];
    const char *s = 0;
    int nl = 0;          /* significant length of s */
    int neg = 0;
    const char *prefix = 0;
    int preflen = 0;
    unsigned long uv;
    long sv;

    if (k == 'd' || k == 'i') {
      if (lng) sv = va_arg(ap, long); else sv = (long)va_arg(ap, int);
      if (sv < 0) { neg = 1; uv = (unsigned long)(-sv); } else uv = (unsigned long)sv;
      nl = __crtl_utoa(num, uv, 10, 0);
      s = num;
      if (neg) { prefix = "-"; preflen = 1; }
      else if (plus) { prefix = "+"; preflen = 1; }
      else if (space) { prefix = " "; preflen = 1; }
    } else if (k == 'u') {
      if (lng) uv = va_arg(ap, unsigned long); else uv = (unsigned long)va_arg(ap, unsigned int);
      nl = __crtl_utoa(num, uv, 10, 0); s = num;
    } else if (k == 'x' || k == 'X') {
      if (lng) uv = va_arg(ap, unsigned long); else uv = (unsigned long)va_arg(ap, unsigned int);
      nl = __crtl_utoa(num, uv, 16, k == 'X'); s = num;
      if (alt && uv != 0) { prefix = (k == 'X') ? "0X" : "0x"; preflen = 2; }
    } else if (k == 'o') {
      if (lng) uv = va_arg(ap, unsigned long); else uv = (unsigned long)va_arg(ap, unsigned int);
      nl = __crtl_utoa(num, uv, 8, 0); s = num;
    } else if (k == 'p') {
      uv = (unsigned long)va_arg(ap, void *);
      nl = __crtl_utoa(num, uv, 16, 0); s = num;
      prefix = "0x"; preflen = 2;
    } else if (k == 'c') {
      one[0] = (char)va_arg(ap, int); one[1] = 0; s = one; nl = 1;
    } else if (k == 's') {
      s = va_arg(ap, const char *);
      if (s == 0) s = "(null)";
      while (s[nl]) nl++;
      if (prec >= 0 && prec < nl) nl = prec;   /* precision caps a string */
    } else if (k == '%') {
      one[0] = '%'; one[1] = 0; s = one; nl = 1;
    } else if (k == 'f' || k == 'F' || k == 'e' || k == 'E' || k == 'g' || k == 'G') {
      /* float formatting: reads a double vararg. BLOCKED by bug-c-double-vararg
         (the double's bits are not in the GP save area yet) — emits a
         placeholder so the field still consumes its arg and width. */
      (void)va_arg(ap, double);
      s = "<float>"; nl = 7;
    } else {
      /* unknown conversion: emit verbatim */
      if (o + 1 < cap) buf[o] = '%'; o++;
      if (o + 1 < cap) buf[o] = k; o++;
      continue;
    }

    /* integer precision: minimum digit count (zero-pad the number, not the field) */
    int zpad = 0;
    if ((k=='d'||k=='i'||k=='u'||k=='x'||k=='X'||k=='o'||k=='p') && prec >= 0) {
      zero = 0;                       /* '0' flag ignored when precision given */
      if (prec > nl) zpad = prec - nl;
    }

    int bodylen = preflen + zpad + nl;
    int pad = width - bodylen;
    int p;

    /* leading spaces (right-justified, space pad) */
    if (!left && !zero) for (p = 0; p < pad; p++) { if (o + 1 < cap) buf[o] = ' '; o++; }
    /* sign / 0x prefix */
    for (p = 0; p < preflen; p++) { if (o + 1 < cap) buf[o] = prefix[p]; o++; }
    /* zero pad (field width, '0' flag) */
    if (!left && zero) for (p = 0; p < pad; p++) { if (o + 1 < cap) buf[o] = '0'; o++; }
    /* precision zeros (number minimum digits) */
    for (p = 0; p < zpad; p++) { if (o + 1 < cap) buf[o] = '0'; o++; }
    /* body */
    for (p = 0; p < nl; p++) { if (o + 1 < cap) buf[o] = s[p]; o++; }
    /* trailing spaces (left-justified) */
    if (left) for (p = 0; p < pad; p++) { if (o + 1 < cap) buf[o] = ' '; o++; }
  }

  if (cap > 0) {
    if (o < cap) buf[o] = 0; else buf[cap - 1] = 0;
  }
  return (int)o;
}

/* ---- buffer entry points (no syscall — exercisable in isolation) ---------- */

int vsnprintf(char *s, size_t n, const char *fmt, va_list ap) {
  return __crtl_vformat(s, n, fmt, ap);
}

int snprintf(char *s, size_t n, const char *fmt, ...) {
  va_list ap; int r;
  va_start(ap, fmt);
  r = __crtl_vformat(s, n, fmt, ap);
  va_end(ap);
  return r;
}

int vsprintf(char *s, const char *fmt, va_list ap) {
  /* no bound — use a very large cap (caller owns a big-enough buffer) */
  return __crtl_vformat(s, (size_t)-1, fmt, ap);
}

int sprintf(char *s, const char *fmt, ...) {
  va_list ap; int r;
  va_start(ap, fmt);
  r = __crtl_vformat(s, (size_t)-1, fmt, ap);
  va_end(ap);
  return r;
}

/* ---- stream output (rides __pxx_write) ------------------------------------ */

/* Render into a fixed stack buffer then push to the fd in one write. lua's
   lines fit comfortably; a >1023-byte single printf truncates (acceptable —
   lua never emits one). */
static int __crtl_vfdprintf(int fd, const char *fmt, va_list ap) {
  char buf[1024];
  int n = __crtl_vformat(buf, sizeof(buf), fmt, ap);
  int w = n;
  if (w > (int)sizeof(buf) - 1) w = (int)sizeof(buf) - 1;
  __pxx_write(fd, buf, (unsigned long)w);
  return n;
}

int vfprintf(FILE *stream, const char *fmt, va_list ap) {
  return __crtl_vfdprintf(stream->fd, fmt, ap);
}

int vprintf(const char *fmt, va_list ap) {
  return __crtl_vfdprintf(1, fmt, ap);
}

int fprintf(FILE *stream, const char *fmt, ...) {
  va_list ap; int r;
  va_start(ap, fmt);
  r = __crtl_vfdprintf(stream->fd, fmt, ap);
  va_end(ap);
  return r;
}

int printf(const char *fmt, ...) {
  va_list ap; int r;
  va_start(ap, fmt);
  r = __crtl_vfdprintf(1, fmt, ap);
  va_end(ap);
  return r;
}

/* ---- byte / string stream API (what lua's lua_writestring etc. call) ------ */

size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream) {
  unsigned long total = (unsigned long)size * (unsigned long)nmemb;
  long w;
  if (total == 0) return 0;
  w = __pxx_write(stream->fd, ptr, total);
  if (w <= 0) { stream->err = 1; return 0; }
  if (size == 0) return 0;
  return (size_t)((unsigned long)w / (unsigned long)size);
}

int fputs(const char *s, FILE *stream) {
  unsigned long n = 0;
  while (s[n]) n++;
  if (__pxx_write(stream->fd, s, n) < 0) { stream->err = 1; return -1; }
  return (int)n;
}

int puts(const char *s) {
  unsigned long n = 0;
  while (s[n]) n++;
  if (__pxx_write(1, s, n) < 0) return -1;
  if (__pxx_write(1, "\n", 1) < 0) return -1;
  return (int)n + 1;
}

int fputc(int c, FILE *stream) {
  char ch = (char)c;
  if (__pxx_write(stream->fd, &ch, 1) < 0) { stream->err = 1; return -1; }
  return c & 0xFF;
}

int putc(int c, FILE *stream) { return fputc(c, stream); }

int putchar(int c) {
  char ch = (char)c;
  if (__pxx_write(1, &ch, 1) < 0) return -1;
  return c & 0xFF;
}

/* ---- input (rides __pxx_read) --------------------------------------------- */

size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream) {
  unsigned long total = (unsigned long)size * (unsigned long)nmemb;
  long r;
  if (total == 0) return 0;
  r = __pxx_read(stream->fd, ptr, total);
  if (r <= 0) { stream->eof = 1; return 0; }
  if (size == 0) return 0;
  return (size_t)((unsigned long)r / (unsigned long)size);
}

int fgetc(FILE *stream) {
  unsigned char ch;
  long r = __pxx_read(stream->fd, &ch, 1);
  if (r <= 0) { stream->eof = 1; return -1; }
  return (int)ch;
}

int getc(FILE *stream) { return fgetc(stream); }

int getchar(void) { return fgetc(&__crtl_stdin); }

char *fgets(char *s, int n, FILE *stream) {
  int i = 0;
  unsigned char ch;
  if (n <= 0) return 0;
  while (i < n - 1) {
    long r = __pxx_read(stream->fd, &ch, 1);
    if (r <= 0) { stream->eof = 1; break; }
    s[i++] = (char)ch;
    if (ch == '\n') break;
  }
  if (i == 0) return 0;
  s[i] = 0;
  return s;
}

/* ---- buffering / status (unbuffered model: no-ops) ------------------------ */

int fflush(FILE *stream) { (void)stream; return 0; }
int feof(FILE *stream) { return stream->eof; }
int ferror(FILE *stream) { return stream->err; }
void clearerr(FILE *stream) { stream->err = 0; stream->eof = 0; }
int setvbuf(FILE *stream, char *buf, int mode, size_t size) { (void)stream; (void)buf; (void)mode; (void)size; return 0; }
void setbuf(FILE *stream, char *buf) { (void)stream; (void)buf; }
