// Interface functions for libac.so
//
#include "ac_slow.hpp"
#include "ac_fast.hpp"
#include "ac.h"

#if defined(USE_SLOW_VER)
typedef struct {
    ac_t ac;
    ACS_Constructor* impl;
} ACS_Header;

extern "C" void*
ac_create(const char** strv, unsigned int* strlenv, unsigned int vect_len) {
    ACS_Constructor* acc = new ACS_Constructor();
    acc->Construct(strv, strlenv, vect_len);
    
    ACS_Header* hdr = new ACS_Header;
    hdr->ac.magic_num = AC_MAGIC_NUM;
    hdr->ac.impl_variant = IMPL_SLOW_VARIANT;
    hdr->impl = acc;
    return (void*)hdr;
}

static inline ac_result_t
_match(ac_t* ac, const char* str, unsigned int len) {
    ASSERT(ac->magic_num == AC_MAGIC_NUM);
    ACS_Constructor* acc = ((ACS_Header*)(void*)ac)->impl;
    Match_Result mr = acc->Match(str, len);
    ac_result_t r;
    r.match_begin = mr.begin;
    r.match_end = mr.end;
    return r;
}

extern "C" ac_result_t
ac_match(void* ac, const char* str, unsigned int len) {
    return _match((ac_t*)ac, str, len);
}

extern "C" int
ac_match2(void* ac, const char* str, unsigned int len) {
    ac_result_t r = _match((ac_t*)ac, str, len);
    return r.match_begin;
}

extern "C" void
ac_free(void* ac) {
    ASSERT(((ac_t*)ac)->magic_num == AC_MAGIC_NUM);
    ACS_Header* hdr = (ACS_Header*)ac;
    
    delete hdr->impl;
    delete hdr;
}

#else
static inline ac_result_t
_match(ac_t* ac, const char* str, unsigned int len) {
    AC_Buffer* buf = (AC_Buffer*)(void*)ac;
    ASSERT(ac->magic_num == AC_MAGIC_NUM); 

    ac_result_t r = Match(buf, str, len);
    return r;
}

extern "C" int
ac_match2(void* ac, const char* str, unsigned int len) {
    ac_result_t r = _match((ac_t*)ac, str, len);
    return r.match_begin;
}

extern "C" ac_result_t
ac_match(void* ac, const char* str, unsigned int len) {
    return _match((ac_t*)ac, str, len);
}

class BufAlloc : public Buf_Allocator {
public:
    virtual AC_Buffer* alloc(int sz) {
        return (AC_Buffer*)(new unsigned char[sz]);
    }

    // Do not de-allocate the buffer when the BufAlloc die.
    virtual void free() {}

    static void myfree(AC_Buffer* buf) {
        ASSERT(buf->hdr.magic_num == AC_MAGIC_NUM); 
        const char* b = (const char*)buf;
        delete[] b;
    }
};

extern "C" void*
ac_create(const char** strv, unsigned int* strlenv, unsigned int v_len) {
    ACS_Constructor acc;
    acc.Construct(strv, strlenv, v_len);

    BufAlloc ba;
    AC_Converter cvt(acc, ba);
    AC_Buffer* buf = cvt.Convert();
    return (ac_t*)(void*)buf;
}

extern "C" void
ac_free(void* ac) {
    BufAlloc::myfree((AC_Buffer*)ac);
}

#endif //USE_SLOW_VER
