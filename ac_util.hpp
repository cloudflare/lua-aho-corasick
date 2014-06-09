#ifndef AC_UTIL_H
#define AC_UTIL_H

#ifdef DEBUG
#include <stdio.h>   // for fprintf
#include <stdlib.h>  // for abort
#endif

typedef unsigned short uint16;
typedef unsigned int uint32;
typedef unsigned long uint64;
typedef unsigned char InputTy;

#ifdef DEBUG
    // Usage examples: ASSERT(a > b),  ASSERT(foo() && "Opps, foo() reutrn 0");
    #define ASSERT(c) if (!(c))\
        { fprintf(stderr, "%s:%d Assert: %s\n", __FILE__, __LINE__, #c); abort(); }
#else
    #define ASSERT(c) ((void)0)
#endif

#define likely(x)   __builtin_expect((x),1)
#define unlikely(x) __builtin_expect((x),0)

#define offsetof(st, m) ((size_t)(&((st *)0)->m))

#define IMPL_SLOW_VARIANT 1
#define IMPL_FAST_VARIANT 2

#endif //AC_UTIL_H
