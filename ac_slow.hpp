#ifndef MY_AC_H
#define MY_AC_H

#include <string.h>
#include <stdio.h>
#include <map>
#include <vector>
#include <algorithm> // for std::sort
#include "ac_util.hpp"

// Forward decl. the acronym "ACS" stands for "Aho-Corasick Slow implementation"
class ACS_State;
class ACS_Constructor;
class AhoCorasick;

using namespace std;

typedef std::map<InputTy, ACS_State*> ACS_Goto_Map;

class Match_Result {
public:
    int begin;
    int end;

    Match_Result(int b, int e): begin(b), end(e) {}
};

typedef pair<InputTy, ACS_State *> GotoPair;
typedef vector<GotoPair> GotoVect;

// Sorting functor
class GotoSort {
public:
    bool operator() (const GotoPair& g1, const GotoPair& g2) {
        return g1.first < g2.first;
    }
};

class ACS_State {
friend class ACS_Constructor;

public:
    ACS_State(uint32 id): _id(id), _depth(0), _is_terminal(false), _fail_link(0) {}
    ~ACS_State() {};

    void Set_Goto(InputTy c, ACS_State* s) { _goto_map[c] = s; }
    ACS_State *Get_Goto(InputTy c) const {
        ACS_Goto_Map::const_iterator iter = _goto_map.find(c);
        return iter != _goto_map.end() ? (*iter).second : 0;
    }

    // Return all transitions sorted in the ascending order of their input.
    void Get_Sorted_Gotos(GotoVect& Gotos) const {
        const ACS_Goto_Map& m = _goto_map;
        Gotos.clear();
        for (ACS_Goto_Map::const_iterator i = m.begin(), e = m.end();
                i != e; i++) {
            Gotos.push_back(GotoPair(i->first, i->second));
        }
        sort(Gotos.begin(), Gotos.end(), GotoSort());
    }
    
    ACS_State* Get_FailLink() const { return _fail_link; }
    uint32 Get_GotoNum() const { return _goto_map.size(); }
    uint32 Get_ID() const { return _id; }
    uint32 Get_Depth() const { return _depth; }
    const ACS_Goto_Map& Get_Goto_Map(void) const { return _goto_map; }
    bool is_Terminal() const { return _is_terminal; }

private:
    uint32 _id;
    short _depth;
    bool _is_terminal;
    ACS_Goto_Map _goto_map;
    ACS_State* _fail_link;
};

class ACS_Constructor {
public:
    ACS_Constructor();
    ~ACS_Constructor();

    void Construct(const char** strv, unsigned int* strlenv,
                   unsigned int strnum);

    Match_Result Match(const char*, uint32 len) const;
    Match_Result Match(const char* s) const { return Match(s, strlen(s)); }
#ifdef DEBUG
    void dump_text(const char* = "ac.txt") const;
    void dump_dot(const char* = "ac.dot") const;
#endif
    const ACS_State *Get_Root_State() const { return _root; }
    const vector<ACS_State*>& Get_All_States() const {
        return _all_states;
    }

    uint32 Get_Next_Node_Id() const { return _next_node_id; }
    uint32 Get_State_Num() const { return _next_node_id - 1; }

private:
    void Add_String(const char* str, unsigned int str_len);
    ACS_State* new_state();
    void Propagate_faillink();

private:
    ACS_State* _root;
    vector<ACS_State*> _all_states;
    unsigned char* _root_char; 
    uint32 _next_node_id;
};

#endif
