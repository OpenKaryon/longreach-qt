// SPDX-License-Identifier: LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
// Copyright (C) 2026 OpenKaryon

#include <float.h>
#include <math.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

// The old NDK declares these interfaces without exporting them in its stubs.
void sincos(double value, double *sine, double *cosine)
{
    *sine = sin(value);
    *cosine = cos(value);
}


void sincosf(float value, float *sine, float *cosine)
{
    *sine = sinf(value);
    *cosine = cosf(value);
}

double log2(double value)
{
    const double inverseLog2 = 1.4426950408889634074;
    if (!(value > 0.0) || value == HUGE_VAL)
        return log(value) * inverseLog2;

    // Keep powers of two exact; mip-level calculations take floor(log2(x)).
    int exponent;
    const double fraction = frexp(value, &exponent);
    return (exponent - 1) + log(fraction * 2.0) * inverseLog2;
}


float log2f(float value)
{
    return (float)log2((double)value);
}

pid_t wait4(pid_t process, int *status, int options, struct rusage *usage)
{
#if defined(__i386__)
    // Gingerbread x86 syscall.S restores the incoming EAX after the kernel
    // call, losing the result. Bionic's exported wait stub preserves it.
    extern pid_t __wait4(pid_t, int *, int, struct rusage *);
    return __wait4(process, status, options, usage);
#else
    return syscall(__NR_wait4, process, status, options, usage);
#endif
}

// These 32-bit Android profiles give long double the native double ABI.
_Static_assert(LDBL_MANT_DIG == DBL_MANT_DIG && LDBL_MAX_EXP == DBL_MAX_EXP
               && sizeof(long double) == sizeof(double), "32-bit Android long-double ABI required");

#define LONGREACH_LONG_DOUBLE_UNARY(name) \
    long double name##l(long double value) { return name((double)value); }
#define LONGREACH_LONG_DOUBLE_BINARY(name) \
    long double name##l(long double left, long double right) \
    { return name((double)left, (double)right); }
LONGREACH_LONG_DOUBLE_UNARY(acosh)
LONGREACH_LONG_DOUBLE_UNARY(acos)
LONGREACH_LONG_DOUBLE_UNARY(asinh)
LONGREACH_LONG_DOUBLE_UNARY(asin)
LONGREACH_LONG_DOUBLE_UNARY(atanh)
LONGREACH_LONG_DOUBLE_UNARY(atan)
LONGREACH_LONG_DOUBLE_UNARY(cbrt)
LONGREACH_LONG_DOUBLE_UNARY(cosh)
LONGREACH_LONG_DOUBLE_UNARY(cos)
LONGREACH_LONG_DOUBLE_UNARY(erfc)
LONGREACH_LONG_DOUBLE_UNARY(erf)
LONGREACH_LONG_DOUBLE_UNARY(exp2)
LONGREACH_LONG_DOUBLE_UNARY(exp)
LONGREACH_LONG_DOUBLE_UNARY(expm1)
LONGREACH_LONG_DOUBLE_UNARY(lgamma)
LONGREACH_LONG_DOUBLE_UNARY(log10)
LONGREACH_LONG_DOUBLE_UNARY(log1p)
LONGREACH_LONG_DOUBLE_UNARY(log2)
LONGREACH_LONG_DOUBLE_UNARY(logb)
LONGREACH_LONG_DOUBLE_UNARY(log)
LONGREACH_LONG_DOUBLE_UNARY(nearbyint)
LONGREACH_LONG_DOUBLE_UNARY(rint)
LONGREACH_LONG_DOUBLE_UNARY(sinh)
LONGREACH_LONG_DOUBLE_UNARY(sin)
LONGREACH_LONG_DOUBLE_UNARY(sqrt)
LONGREACH_LONG_DOUBLE_UNARY(tanh)
LONGREACH_LONG_DOUBLE_UNARY(tan)
LONGREACH_LONG_DOUBLE_UNARY(tgamma)
LONGREACH_LONG_DOUBLE_BINARY(atan2)
LONGREACH_LONG_DOUBLE_BINARY(fmod)
LONGREACH_LONG_DOUBLE_BINARY(hypot)
LONGREACH_LONG_DOUBLE_BINARY(pow)
LONGREACH_LONG_DOUBLE_BINARY(remainder)

#undef LONGREACH_LONG_DOUBLE_UNARY
#undef LONGREACH_LONG_DOUBLE_BINARY

long long llrintl(long double value) { return llrint((double)value); }

long lrintl(long double value) { return lrint((double)value); }

long double nanl(const char *tag) { (void)tag; return NAN; }

long double modfl(long double value, long double *integer)
{
    double part;
    const double fraction = modf((double)value, &part);
    *integer = part;
    return fraction;
}

long double remquol(long double left, long double right, int *quotient)
{
    return remquo((double)left, (double)right, quotient);
}
