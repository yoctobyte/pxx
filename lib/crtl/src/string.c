/*
 * C runtime: string / memory helpers.
 *
 * Small, project-owned implementations used by source-backed C libraries.
 * Not a complete hosted libc.
 */

#include <stddef.h>
#include <string.h>

void *memcpy(void *dest, const void *src, size_t n)
{
    unsigned char *d = dest;
    const unsigned char *s = src;
    while (n > 0) {
        *d++ = *s++;
        n--;
    }
    return dest;
}

void *memmove(void *dest, const void *src, size_t n)
{
    unsigned char *d = dest;
    const unsigned char *s = src;
    if (d == s || n == 0)
        return dest;
    if (d < s) {
        while (n > 0) {
            *d++ = *s++;
            n--;
        }
    } else {
        d += n;
        s += n;
        while (n > 0) {
            *--d = *--s;
            n--;
        }
    }
    return dest;
}

void *memset(void *s, int c, size_t n)
{
    unsigned char *p = s;
    unsigned char v = (unsigned char)c;
    while (n > 0) {
        *p++ = v;
        n--;
    }
    return s;
}

int memcmp(const void *s1, const void *s2, size_t n)
{
    const unsigned char *a = s1;
    const unsigned char *b = s2;
    while (n > 0) {
        if (*a != *b)
            return (int)*a - (int)*b;
        a++;
        b++;
        n--;
    }
    return 0;
}

size_t strlen(const char *s)
{
    size_t n = 0;
    while (s[n] != '\0')
        n++;
    return n;
}

int strcmp(const char *a, const char *b)
{
    while (*a != '\0' && *a == *b) {
        a++;
        b++;
    }
    return (int)(unsigned char)*a - (int)(unsigned char)*b;
}

int strncmp(const char *a, const char *b, size_t n)
{
    while (n > 0 && *a != '\0' && *a == *b) {
        a++;
        b++;
        n--;
    }
    if (n == 0)
        return 0;
    return (int)(unsigned char)*a - (int)(unsigned char)*b;
}

char *strcpy(char *dest, const char *src)
{
    char *d = dest;
    while ((*d++ = *src++) != '\0')
        ;
    return dest;
}

char *strncpy(char *dest, const char *src, size_t n)
{
    char *d = dest;
    while (n > 0 && *src != '\0') {
        *d++ = *src++;
        n--;
    }
    while (n > 0) {
        *d++ = '\0';
        n--;
    }
    return dest;
}

char *strchr(const char *s, int c)
{
    char ch = (char)c;
    while (*s != '\0') {
        if (*s == ch)
            return (char *)s;
        s++;
    }
    if (ch == '\0')
        return (char *)s;
    return NULL;
}

char *strrchr(const char *s, int c)
{
    const char *last = NULL;
    char ch = (char)c;
    do {
        if (*s == ch)
            last = s;
    } while (*s++ != '\0');
    return (char *)last;
}

void *memchr(const void *s, int c, size_t n)
{
    const unsigned char *p = s;
    unsigned char ch = (unsigned char)c;
    while (n > 0) {
        if (*p == ch)
            return (void *)p;
        p++;
        n--;
    }
    return NULL;
}

char *strcat(char *dest, const char *src)
{
    char *d = dest;
    while (*d != '\0')
        d++;
    while ((*d++ = *src++) != '\0')
        ;
    return dest;
}

char *strncat(char *dest, const char *src, size_t n)
{
    char *d = dest;
    while (*d != '\0')
        d++;
    while (n > 0 && *src != '\0') {
        *d++ = *src++;
        n--;
    }
    *d = '\0';
    return dest;
}

size_t strspn(const char *s, const char *accept)
{
    size_t n = 0;
    while (*s != '\0') {
        if (strchr(accept, *s) == NULL)
            break;
        s++;
        n++;
    }
    return n;
}

size_t strcspn(const char *s, const char *reject)
{
    size_t n = 0;
    while (*s != '\0') {
        if (strchr(reject, *s) != NULL)
            break;
        s++;
        n++;
    }
    return n;
}

char *strpbrk(const char *s, const char *accept)
{
    while (*s != '\0') {
        if (strchr(accept, *s) != NULL)
            return (char *)s;
        s++;
    }
    return NULL;
}

char *strstr(const char *haystack, const char *needle)
{
    size_t nlen = strlen(needle);
    if (nlen == 0)
        return (char *)haystack;
    while (*haystack != '\0') {
        if (strncmp(haystack, needle, nlen) == 0)
            return (char *)haystack;
        haystack++;
    }
    return NULL;
}

int strcoll(const char *a, const char *b)
{
    return strcmp(a, b);
}

size_t strxfrm(char *dest, const char *src, size_t n)
{
    size_t len = strlen(src);
    size_t i = 0;
    if (n > 0) {
        while (i + 1 < n && src[i] != '\0') {
            dest[i] = src[i];
            i++;
        }
        dest[i] = '\0';
    }
    return len;
}

char *strerror(int errnum)
{
    (void)errnum;
    return "error";
}
