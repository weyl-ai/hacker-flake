// cuda-gcc15-compat.h
// Fix CUDA macro conflicts with GCC 15 libstdc++
//
// CUDA's host_defines.h defines macros like __noinline__ as full attribute
// expressions: __attribute__((noinline))
//
// But GCC 15's libstdc++ uses them as attribute names in larger lists:
// __attribute__((__noinline__, __noclone__, __cold__))
//
// This causes invalid nested attributes. Fix by redefining as just names.

#pragma once

#ifdef __CUDACC__
#ifdef __noinline__
#undef __noinline__
#define __noinline__ noinline
#endif

#ifdef __noclone__
#undef __noclone__
#define __noclone__ noclone
#endif

#ifdef __cold__
#undef __cold__
#define __cold__ cold
#endif
#endif
