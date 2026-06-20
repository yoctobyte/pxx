#ifndef PXX_CRTL_WCTYPE_H
#define PXX_CRTL_WCTYPE_H 1

#include <wchar.h>

typedef int wctype_t;
typedef int wctrans_t;

int iswalnum(wint_t c);
int iswalpha(wint_t c);
int iswblank(wint_t c);
int iswcntrl(wint_t c);
int iswdigit(wint_t c);
int iswgraph(wint_t c);
int iswlower(wint_t c);
int iswprint(wint_t c);
int iswpunct(wint_t c);
int iswspace(wint_t c);
int iswupper(wint_t c);
int iswxdigit(wint_t c);
int iswctype(wint_t c, wctype_t desc);
wctype_t wctype(const char *property);
wint_t towlower(wint_t c);
wint_t towupper(wint_t c);

#endif
