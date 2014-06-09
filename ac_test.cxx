#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>

#include <stdio.h>
#include <string.h>
#include <vector>
#include <string>
#include "ac.h"
#include "ac_util.hpp"

using namespace std;

/////////////////////////////////////////////////////////////////////////
//
//         Test using strings from input files     
//
/////////////////////////////////////////////////////////////////////////
//
class BigFileTester {
public:
    BigFileTester(const char* filepath);
    bool Test();

private:
    bool GenerateKeys();
    bool TestCore();
    void PrintStr(FILE*, const char* str, int len);

private:
    const char* _filepath;
    vector<string> _keys;
    const char* _msg;
    int _msg_len;
    int _key_num;     // number of strings in dictionary
    int _chunk_sz;
};

BigFileTester::BigFileTester(const char* filepath) {
    _filepath = filepath;
    _msg = 0;
    _msg_len = 0;
    _key_num = 0;
    _chunk_sz = 0;
}

void
BigFileTester::PrintStr(FILE* f, const char* str, int len) {
    fprintf(f, "{");
    for (int i = 0; i < len; i++) {
        unsigned char c = str[i];
        if (isprint(c))
           fprintf(f, "'%c', ", c);
        else
           fprintf(f, "%#x, ", c);
    }
    fprintf(f, "}");
};

bool
BigFileTester::GenerateKeys() {
    int chunk_sz = 4096;
    int max_key_num = 100;
    int key_min_len = 8;
    int key_max_len = 40;

    int t = _msg_len / chunk_sz;
    int keynum = t > max_key_num ? max_key_num : t;

    if (keynum <= 4) {
        // file is too small
        return false;
    }
    chunk_sz = _msg_len / keynum;
    _chunk_sz = chunk_sz;

    // For each chunck, "randomly" grab a sub-string searving
    // as key.
    int random_ofst[] = { 12, 30, 23, 15 };
    int rofstsz = sizeof(random_ofst)/sizeof(random_ofst[0]);
    int ofst = 0;
    const char* msg = _msg;
    for (int idx = 0; idx < keynum - 1; idx++) {
        const char* key = msg + ofst + idx % rofstsz;
        int key_len = key_min_len + idx % (key_max_len - key_min_len);
        _keys.push_back(string(key, key_len));
        ofst += chunk_sz; 
    }
    return true;
}

bool
BigFileTester::TestCore() {
    if (!GenerateKeys())
        return false;

    const char **keys = new const char*[_keys.size()];
    int i = 0;
    for (vector<string>::iterator si = _keys.begin(), se = _keys.end();
         si != se; si++, i++) {
        keys[i] = si->c_str();
    }

    void* ac = ac_create(keys, i);
    delete[] keys;
    keys = 0;

    if (!ac)
        return false;

    int fail = 0;
    // advance one chunk at a time.
    for (int ofst = 0, len = _msg_len, chunk_sz = _chunk_sz;
         ofst < len - chunk_sz; ofst += chunk_sz) {
        const char* substring = _msg + ofst;
        ac_result_t r = ac_match(ac, substring , len - ofst);
        int m_b = r.match_begin;
        int m_e = r.match_end;

        if (m_b < 0 || m_e < 0 || m_e <= m_b || m_e >= len) {
            fprintf(stdout, "fail to find match substring[%d:%d])\n",
                    ofst, len - 1);
            fail ++;
            continue;
        }
        
        const char* match_str = _msg + len;
        int strstr_len = 0;
        int key_idx = -1;
        
        for (int i = 0, e = _keys.size(); i != e; i++) {
            const char* key = _keys[i].c_str();
            if (const char *m = strstr(substring, key)) {
                if (m < match_str) {
                    match_str = m;
                    strstr_len = strlen(key);
                    key_idx = i;
                }
            }
        }
        ASSERT(key_idx != -1);
        if ((match_str - substring != m_b)) {
            fprintf(stdout,
                   "Fail to find match substring[%d:%d]),"
                   " expected to find match at offset %d instead of %d\n",
                    ofst, len - 1,
                    (int)(match_str - _msg), ofst + m_b);
            fprintf(stdout, "%d vs %d (key idx %d)\n", strstr_len, m_e - m_b + 1, key_idx);
            PrintStr(stdout, match_str, strstr_len);
            fprintf(stdout, "\n");
            PrintStr(stdout, _msg + ofst + m_b,
                     m_e - m_b + 1);
            fprintf(stdout, "\n");
            fail ++;
        }
    }

    ac_free(ac);
    return fail == 0;
}

bool
BigFileTester::Test() {
    fprintf(stdout, "Testing using file '%s'...\n", _filepath);

    int fd = ::open(_filepath, O_RDONLY);
    if (fd == -1) {
        perror("open");
        return false;
    }
        
    struct stat sb;
    if (fstat(fd, &sb) == -1) {
        perror("fstat");
        return false;
    }

    if (!S_ISREG (sb.st_mode)) {
        fprintf(stderr, "%s is not regular file\n", _filepath);
        return false;
    }

    int ten_M = 1024 * 1024 * 10;
    int map_sz = sb.st_size > ten_M ? ten_M : sb.st_size;
    char* p = (char*)mmap (0, map_sz, PROT_READ|PROT_WRITE, MAP_PRIVATE, fd, 0);
    if (p == MAP_FAILED) {
        perror("mmap");
        close(fd);
        return false;
    }

    // Remote NULL
    for (int i = 0; i < map_sz; i++) { if (!p[i]) p[i] = 'a'; }
    p[map_sz - 1] = 0;
    _msg = (const char*)p;
    _msg_len = map_sz;
    
    bool res = TestCore();

    munmap(p, map_sz);
    close(fd);

    fprintf(stdout, "%s\n", res ? "succ" : "fail");
    return res;
}

/////////////////////////////////////////////////////////////////////////
//
//          Simple (yet maybe tricky) testings
//
/////////////////////////////////////////////////////////////////////////
//
typedef struct {
    const char* str;
    const char* match;
} StrPair;

typedef struct {
    const char* name;
    const char** dict;
    StrPair* strpairs;
    int dict_len;
    int strpair_num;
} TestingCase;

class Tests {
public:
    Tests(const char* name,
          const char* dict[], int dict_len,
          StrPair strpairs[], int strpair_num) {
        if (!_tests)
            _tests = new vector<TestingCase>;
        
        TestingCase tc;
        tc.name = name;
        tc.dict = dict;
        tc.strpairs = strpairs;
        tc.dict_len = dict_len;
        tc.strpair_num = strpair_num;
        _tests->push_back(tc);
    }

    static vector<TestingCase>* Get_Tests() { return _tests; }
    static void Erase_Tests() { delete _tests; _tests = 0; }

private:
    static vector<TestingCase> *_tests;
};

vector<TestingCase>* Tests::_tests = 0;

static int
simple_test(void) {
    int total = 0;
    int fail = 0;

    vector<TestingCase> *tests = Tests::Get_Tests();
    if (!tests)
        return 0;

    for (vector<TestingCase>::iterator i = tests->begin(), e = tests->end();
            i != e; i++) {
        TestingCase& t = *i;
        fprintf(stdout, ">Testing %s\nDictionary:[ ", t.name);
        for (int i = 0, e = t.dict_len, need_break=0; i < e; i++) {
            fprintf(stdout, "%s, ", t.dict[i]);
            if (need_break++ == 16) {
                fputs("\n  ", stdout);
                need_break = 0;
            }
        }
        fputs("]\n", stdout);

        /* Create the dictionary */
        int dict_len = t.dict_len;
        void* ac = ac_create(t.dict, dict_len);

        for (int ii = 0, ee = t.strpair_num; ii < ee; ii++, total++) {
            const StrPair& sp = t.strpairs[ii];
            const char *str = sp.str; // the string to be matched
            const char *match = sp.match;

            fprintf(stdout, "[%3d] Testing '%s' : ", total, str);

            int len = strlen(str);
            ac_result_t r = ac_match(ac, str, len);
            int m_b = r.match_begin;
            int m_e = r.match_end;

            // The return value per se is insane.
            if (m_b > m_e ||
                ((m_b < 0 || m_e < 0) && (m_b != -1 || m_e != -1))) {
                fprintf(stdout, "Insane return value (%d, %d)\n", m_b, m_e);
                fail ++;
                continue;
            }
            
            // If the string is not supposed to match the dictionary.
            if (!match) {
                if (m_b != -1 || m_e != -1) {
                    fail ++;
                    fprintf(stdout, "Not Supposed to match (%d, %d) \n",
                            m_b, m_e);
                } else
                    fputs("Pass\n", stdout);
                continue;
            }

            // The string or its substring is match the dict.
            if (m_b >= len || m_b >= len) {
                fail ++;
                fprintf(stdout,
                        "Return value >= the length of the string (%d, %d)\n",
                        m_b, m_e);
                continue;
            } else {
                int mlen = strlen(match);
                if ((mlen != m_e - m_b + 1) ||
                    strncmp(str + m_b, match, mlen)) {
                    fail ++;
                    fprintf(stdout, "Fail\n");
                } else
                    fprintf(stdout, "Pass\n");
            }
        }
        fputs("\n", stdout);
        ac_free(ac);
    }

    fprintf(stdout, "Total : %d, Fail %d\n", total, fail);

    return fail ? -1 : 0;
}

int
main (int argc, char** argv) {
    int res = simple_test();
    bool succ = res == 0 ? true : false;
    
    for (int i = 1; i < argc; i++) {
        BigFileTester bft(argv[i]);
        succ = bft.Test() && succ;
    }

    return succ ? 0 : -1;
};

/* test 1*/
const char *dict1[] = {"he", "she", "his", "her"};
StrPair strpair1[] = {
    {"he", "he"}, {"she", "she"}, {"his", "his"},
    {"hers", "he"}, {"ahe", "he"}, {"shhe", "he"},
    {"shis2", "his"}, {"ahhe", "he"}
};
Tests test1("test 1",
            dict1, sizeof(dict1)/sizeof(dict1[0]), 
            strpair1, sizeof(strpair1)/sizeof(strpair1[0]));

/* test 2*/
const char *dict2[] = {"poto", "poto"}; /* duplicated strings*/
StrPair strpair2[] = {{"The pot had a handle", 0}};
Tests test2("test 2", dict2, 2, strpair2, 1);

/* test 3*/
const char *dict3[] = {"The"};
StrPair strpair3[] = {{"The pot had a handle", "The"}};
Tests test3("test 3", dict3, 1, strpair3, 1);

/* test 4*/
const char *dict4[] = {"pot"};
StrPair strpair4[] = {{"The pot had a handle", "pot"}};
Tests test4("test 4", dict4, 1, strpair4, 1);

/* test 5*/
const char *dict5[] = {"pot "};
StrPair strpair5[] = {{"The pot had a handle", "pot "}};
Tests test5("test 5", dict5, 1, strpair5, 1);

/* test 6*/
const char *dict6[] = {"ot h"};
StrPair strpair6[] = {{"The pot had a handle", "ot h"}};
Tests test6("test 6", dict6, 1, strpair6, 1);

/* test 7*/
const char *dict7[] = {"andle"};
StrPair strpair7[] = {{"The pot had a handle", "andle"}};
Tests test7("test 7", dict7, 1, strpair7, 1);
