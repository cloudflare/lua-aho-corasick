#ifndef AC_H
#define AC_H
#ifdef __cplusplus
extern "C" {
#endif

#define AC_EXPORT __attribute__ ((visibility ("default")))

#define AC_MAGIC_NUM 0x5a
typedef struct {
    unsigned char magic_num;
    unsigned char impl_variant;
} ac_t;

typedef struct {
    int match_begin;
    int match_end;
} ac_result_t;

ac_t* ac_create(const char **str_vect, unsigned int vect_len) AC_EXPORT ;

ac_result_t ac_match(ac_t*, const char *str, unsigned int len) AC_EXPORT ;

/* Similar to ac_match() except that it only returns match-begin. The rationale
 * for this interface is that luajit has hard time in dealing with strcture-
 * return-value.
 */
int ac_match2(ac_t*, const char *str, unsigned int len) AC_EXPORT ;

void ac_free(ac_t*) AC_EXPORT;

#ifdef __cplusplus
}
#endif

#endif /* AC_H */
