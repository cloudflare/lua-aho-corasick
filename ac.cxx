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

extern "C" ac_t*
ac_create(const char **str, unsigned int len) {
    ACS_Constructor *acc = new ACS_Constructor();
    acc->Construct(str, len);
    
    ACS_Header* hdr = new ACS_Header;
    hdr->ac.magic_num = AC_MAGIC_NUM;
    hdr->ac.impl_variant = IMPL_SLOW_VARIANT;
    hdr->impl = acc;
    return (ac_t*)(void*)hdr;
}

static inline ac_result_t
_match(ac_t *ac, const char *str, unsigned int len) {
    ASSERT(ac->magic_num == AC_MAGIC_NUM);
    ACS_Constructor *acc = ((ACS_Header*)(void*)ac)->impl;
    Match_Result mr = acc->Match(str, len);
    ac_result_t r;
    r.match_begin = mr.begin;
    r.match_end = mr.end;
    return r;
}

extern "C" ac_result_t
ac_match(ac_t *ac, const char *str, unsigned int len) {
    return _match(ac, str, len);
}

extern "C" int
ac_match2(ac_t *ac, const char *str, unsigned int len) {
    ac_result_t r = _match(ac, str, len);
    return r.match_begin;
}

extern "C" void
ac_free(ac_t* ac) {
    ASSERT(ac->magic_num == AC_MAGIC_NUM);
    ACS_Header* hdr = (ACS_Header*)(void*)ac;
    
    delete hdr->impl;
    delete hdr;
}

#else

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

extern "C" ac_t*
ac_create(const char **str, unsigned int len) {
    ACS_Constructor acc;
    BufAlloc ba;
    acc.Construct(str, len);
    AC_Converter cvt(acc, ba);
    AC_Buffer* buf = cvt.Convert();
    return (ac_t*)(void*)buf;
}

static inline ac_result_t
_match(ac_t* ac, const char *str, unsigned int len) {
    AC_Buffer* buf = (AC_Buffer*)(void*)ac;
    ASSERT(ac->magic_num == AC_MAGIC_NUM); 

    ac_result_t r = Match(buf, str, len);
    return r;
}

extern "C" ac_result_t
ac_match(ac_t* ac, const char *str, unsigned int len) {
    return _match(ac, str, len);
}

extern "C" int
ac_match2(ac_t* ac, const char *str, unsigned int len) {
    ac_result_t r = _match(ac, str, len);
    return r.match_begin;
}

extern "C" void
ac_free(ac_t* ac) {
    BufAlloc::myfree((AC_Buffer*)ac);
}

#endif //USE_SLOW_VER
