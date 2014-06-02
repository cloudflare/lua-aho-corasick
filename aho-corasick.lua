--  Copyright (c) 2014 CloudFlare, Inc. All rights reserved.
--
--  Redistribution and use in source and binary forms, with or without
--  modification, are permitted provided that the following conditions are
--  met:
--
--     * Redistributions of source code must retain the above copyright
--  notice, this list of conditions and the following disclaimer.
--     * Redistributions in binary form must reproduce the above
--  copyright notice, this list of conditions and the following disclaimer
--  in the documentation and/or other materials provided with the
--  distribution.
--     * Neither the name of CloudFlare, Inc. nor the names of its
--  contributors may be used to endorse or promote products derived from
--  this software without specific prior written permission.
--
--  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
--  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
--  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
--  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
--  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
--  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
--  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
--  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
--  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
--  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
--  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

--
--   This module implement Aho-corasick string matching algorithm (hereinafter
-- we call it AC algorithm for short).
--
--   For efficiency purpose, we construct the graph twice, one using convenient
-- yet inefficient data structure, which is immediately converted to an efficient
-- yet awkward representation. To avoid unnecesesary confusion, we call the
-- first and second graph "state machine" and "AC graph", respectively.
--
--   We believe the efficency arises from two important factors:
--    1. It uses much more compact data structure thanks to FFI
--    2. It use binary search upon sorted array instead of hash-table to
--       determine the outcome of state transition (i.e. the goto(input)
--       function).
--
--   Again for the efficiency reasons, this implementation is slightly different
-- from the standard AC algorithm: If a string's sub-string matches multiple
-- strings represented by the AC graph, only one match is returned.
--
-- o.There are two interface functions
--
--  1. build(strs)
--     where the strs is a vector of strings. If successful, it returns the
--     AC graph represented as a pair, with first element being the root of
--     the AC graph, and and second element being the buffer accommodating
--     the entire AC graph; otherwise, it returns nil.
--
--  2. match(acgraph, str)
--     The first parameter is the AC graph returned from build(), and second
--     parameter is string to be machined. If the string matches the AC graph
--     the range of sub-string is returned to the caller; otherwise,
--
-- o. Here is a usage example:
--    --------------------------------------------------------------
--      local AC = require 'aho-corasick'
--      local tab = {"he", "she", "his", "her"}
--      local graph = AC.new(tab)
--
--      local str = "shis2"
--      local b, e = AC.match(graph, str)
--      if b then
--        io.write(string.format("%s[%d:%d] matches\n", str, b, e))
--      end
--   ----------------------------------------------------------------
--  Executing this example will yeild : "shis2[2:4] matches", meaning substring
--  from position 2 to 4, inclusively, maches one of strings respreneted by the
--  AC graph.
--
-- o. CAVEAT:
--    To reduce memory allocation overhead, and also to reduce the size of pointer
--  we allocate a consecutive chunk of memory to accommodate the entire graph,
--  which may not work for big or huge graph.
--
-- o. Troubleshooting
--   Setting variable DEBUG to non-nil will enable dummping the state machine
-- to a plain-text file ac.txt and a dotty format file ac.dot.
--

local ffi = require "ffi"
local ffi_new = ffi.new
local ffi_sizeof = ffi.sizeof
local ffi_offsetof = ffi.offsetof
local ffi_cast = ffi.cast
local uchar_ptr_t = ffi.typeof("unsigned char*")
local uchar_t = ffi.typeof("unsigned char")
local tab_sort = table.sort

local str_byte = string.byte

local bnot = bit.bnot
local band = bit.band
local bor = bit.bor
local brshift = bit.rshift

local M = {}

-- ///////////////////////////////////////////////////////////////////////////
--
--    Following code is to manipulate Aho-Corasick graph.
--
-- ///////////////////////////////////////////////////////////////////////////
--
ffi.cdef[[
  /* ID of an AC node. An AC node is indentified by the index of its first
   * slab.
   */
  typedef unsigned int ACNODE_ID;
  typedef unsigned char AC_INPUT;

  typedef struct {
    ACNODE_ID fail_link;

    /* depth from root node */
    unsigned short depth;

    /* magic_num_flags holds "0x5a | 0" or "0x5a | 1". The least
     * significant bit is set for terminal state, and cleared otherwise.
     */
    unsigned char magic_num_flags;

    /* The number of possible next state */
    unsigned char goto_num;

    /* Ascending-sorted array of possible input char; it has as many as
     * <goto_num> elements
     */
    AC_INPUT input[1];

    /* goto_state[i] is corresponding to input[i] */
    /* ACNODE_ID goto_state[n] */
  } AC_NODE;
]]

local ACNODE_ID_t       = ffi.typeof("ACNODE_ID")
local ACNODEID_ptr_t    = ffi.typeof("ACNODE_ID*")
local ACNODE_ID_alignof = ffi.alignof("ACNODE_ID")
local ACNODE_ID_sizeof  = ffi.sizeof("ACNODE_ID")

local AC_NODE_t         = ffi.typeof("AC_NODE")
local AC_NODE_ptr_t     = ffi.typeof("AC_NODE*")
local AC_NODE_alignof   = ffi.alignof("AC_NODE")

local AC_INPUT_sizeof   = ffi.sizeof("AC_INPUT")

-- Given the number of goto-states, return the size in byte of the AC node.
--
local function _ac_calc_node_sz (goto_num)
  -- Offset of "input" field
  local input_ofst = ffi_offsetof(AC_NODE_t, "input")

  -- Input_end points to the end of input vector. We allocate one more element
  -- to abviate the need of conditional branch like this (in C):
  --  input_end = goto_num == 0 ? input_ofst + goto_num : input_ofst + 1
  --
  local input_end = input_ofst + (goto_num + 1) * AC_INPUT_sizeof
  local goto_state_ofst = band(input_end + ACNODE_ID_alignof - 1,
                               bnot(ACNODE_ID_alignof - 1))

  local goto_state_end = goto_state_ofst + goto_num * ACNODE_ID_sizeof
  local sz = band(goto_state_end + AC_NODE_alignof - 1,
                  bnot(AC_NODE_alignof - 1))
  return sz
end

-- Return the vector of goto-state of the specified AC node
-- NOTE: keep in sync with __ac_calc_node_sz()
local function _ac_get_goto_vect(state)
  local input_ofst = ffi_offsetof(AC_NODE_t, "input")
  local input_end = input_ofst + (state.goto_num + 1) * AC_INPUT_sizeof

  local goto_state_ofst = band(input_end + ACNODE_ID_alignof - 1,
                               bnot(ACNODE_ID_alignof - 1))
  local t = ffi_cast(uchar_ptr_t, state) + goto_state_ofst
  return ffi_cast(ACNODEID_ptr_t, t)
end

-- ///////////////////////////////////////////////////////////////////////////
--
--   Following code is about state machine. As we mentioned above, the
-- "state machine" in this module refers to the AC group with convenient
-- yet inefficient data structure.
--
-- ///////////////////////////////////////////////////////////////////////////
--

-- State (of state machine) has bunch of fields comprising its "array part"
--
-- state[1] is a hash table, keeping track of transition, i.e
--   the goto-function.
-- state[2] is an array, collecting all the possible valid inputs.
-- state[3] is the "failure" link
-- state[4] is the depth of the state from root state
-- state[5] is for misc annotation
-- state[6] is for debugging id, state has debugging ID, starting from 1
--
local STATE_GOTO      = 1
local STATE_INPUT     = 2
local STATE_FAILURE   = 3
local STATE_DEPTH     = 4
local STATE_OFST      = 5
local STATE_DEBUG_ID  = 6

local DEBUG = nil
local debug_id_num = 0

local function _sm_create_state()
  local s = {{}, {}, 0, 0, 0, debug_id_num}
  s[STATE_INPUT][0] = 0 -- init the length of input vector
  debug_id_num = debug_id_num + 1
  return s
end

-- Return the target state of the transition from specified state and input. If
-- the transition does't exist, add it to the state machine, and return the
-- target state.
--
local function _sm_goto(cur_state, input)
  local targ_state = cur_state[STATE_GOTO][input]

  if not targ_state then
    targ_state = _sm_create_state()
    cur_state[STATE_GOTO][input] = targ_state

    -- Add the new input to the set
    local input_set = cur_state[STATE_INPUT]
    local sz = input_set[0]
    input_set[sz + 1] = input
    input_set[0] = sz + 1

    -- set the depth of the target state
    targ_state[STATE_DEPTH] = cur_state[STATE_DEPTH] + 1
  end
  return targ_state
end

-- Helper function of M.build(). It is to build a state machine for the
-- input strings "strs", using convenient yet inefficient data structures,
-- and returns a vector containing all states along with the size of
-- the vector.
--
local function _sm_build(strs)
  local strnum = #strs
  if strnum == 0 then
    return nil
  end

  -- Init the node id; it is for debugging purpose only
  debug_id_num = 1

  local root = _sm_create_state()
  root[STATE_FAILURE] = nil

  -- step 1: Loop over all input strings, constructing the goto-functions
  all_state = {root}
  for i = 1, strnum do
    local str = strs[i]

    -- Create nodes when iterating all the chars of the current string.
    local state = root
    for charidx = 1, #str do
      local c = str_byte(str, charidx)
      state = _sm_goto(state, c)
    end

    -- mark the last state as a terminal state
    state.is_terminal = 1
  end

  -- step 2: BFS the state machine, propagating the failure-link top-down.
  local worklist = {root}
  local goto_func = root[STATE_GOTO]
  local input_set = root[STATE_INPUT]
  local goto_state
  local sz = 1

  -- Place root's goto-states in the worklist.
  for i = 1, input_set[0] do
    goto_state = goto_func[input_set[i]]
    goto_state[STATE_FAILURE] = root

    sz = sz + 1
    worklist[sz] = goto_state
  end

  -- Loop until the worklist become empty
  local idx = 2 -- skip root node
  while idx <= sz do
    local s = worklist[idx]
    idx = idx + 1

    goto_func = s[STATE_GOTO]
    input_set = s[STATE_INPUT]
    fail_link = s[STATE_FAILURE]

    for i = 1, input_set[0] do
      local c = input_set[i]
      goto_state = goto_func[c]
      sz = sz + 1
      worklist[sz] = goto_state

      local fs = fail_link
      -- Walk along the fail-link until we come across the root or a node where
      -- goto(c) is valid
      while not fs[STATE_GOTO][c] and fs ~= root do
        fs = fs[STATE_FAILURE]
      end

      -- Just in case fs == root, "fs[STATE_GOTO][c]" could be nil, in that
      -- case, the fail(goto-state) should be set to "root"
      goto_state[STATE_FAILURE] = fs[STATE_GOTO][c] or root
    end
  end
  return worklist, sz
end

local function _sm_dump_text(state_vect, vect_sz)
  local string_fmt = string.format
  local file = io.open("ac.txt", "w+")

  for i = 1, vect_sz do
    local state = state_vect[i]
    file:write(string_fmt("S:%d ofst:%d goto {",
                          state[STATE_DEBUG_ID], state[STATE_OFST]))

    local gotofunc = state[STATE_GOTO]
    local input_vect = state[STATE_INPUT]
    for j = 1, #state[STATE_INPUT] do
      local c = input_vect[j]
      file:write(string_fmt("%c -> S:%d,", c, gotofunc[c][STATE_DEBUG_ID]))
    end

    local f = state[STATE_FAILURE]
    if f then
      file:write(string_fmt("} fail-link: %d\n", f[STATE_DEBUG_ID]))
    else
      file:write("} fail-link: nil\n")
    end
  end
    
  io.close(file)
end

local function _sm_dump_dot(state_vect, vect_sz)
  local string_fmt = string.format
  local root = state_vect[1]
  
  local string_fmt = string.format
  local file = io.open("ac.dot", "w+")
  local indent = "  "

  -- Emit prologue
  file:write("digraph G {\n")
  
  -- Emit node attribute
  file:write(string_fmt("%s%d [style=filled];\n",
                        indent, root[STATE_DEBUG_ID]))
  for i = 2, vect_sz do
    local s = state_vect[i]
    if s.is_terminal then
      file:write(string_fmt("%s%d [shape=doublecircle];\n",
                            indent, s[STATE_DEBUG_ID]))
    end
  end
  
  -- Emit edges
  for i = 1, vect_sz do
    local s = state_vect[i]
    local sid = s[STATE_DEBUG_ID]
    local inputs = s[STATE_INPUT]
    for j = 1, #s[STATE_INPUT] do
      local c = inputs[j]
      local sink = s[STATE_GOTO][c]
      file:write(string_fmt("%s%d -> %d [label=%c];\n",
                            indent, sid, sink[STATE_DEBUG_ID], c))
    end

    local fail = s[STATE_FAILURE]
    if fail and fail ~= root then
      file:write(string_fmt("%s%d -> %d [style=dotted, color=red];\n",
                             indent, sid, fail[STATE_DEBUG_ID]))
    end
  end

  -- Emit epilogue
  file:write("}")
end

local function _sm_dump(state_vect, vect_sz)
  _sm_dump_text(state_vect, vect_sz)
  _sm_dump_dot(state_vect, vect_sz)
  print("State machine was dumped to ac.txt (plaint-text) and ac.dot (dotty format)")
end

local function _convert(state_vect, vect_sz)

  -- Reserve some space, such such (ACNODE_ID)0 implies invalid state.
  local reserve = _ac_calc_node_sz(0)

  -- step 1: Compute the size of memory allocated for the AC graph
  local mem_sz = reserve
  for i = 1, vect_sz do
    local state = state_vect[i]
    state[STATE_OFST] = mem_sz
    mem_sz = mem_sz + _ac_calc_node_sz(state[STATE_INPUT][0])
  end

  if DEBUG then
    _sm_dump(state_vect, vect_sz)
  end

  -- step 2: Allocate a chunk of memory to accommodate the entire graph
  --   TODO: We need better allocation scheme for big graph.
  local buffer = ffi_new("unsigned char[?]", mem_sz)

  -- step 3: Convert state one by one
  local root = state_vect[1]
  for i = 1, vect_sz do
    local state = state_vect[i]
    local ac_node = ffi_cast(AC_NODE_ptr_t, buffer + state[STATE_OFST])

    local f = state[STATE_FAILURE]
    if f then
      ac_node.fail_link = f[STATE_OFST]
    else
      if state ~= root then
        return nil -- this is a bug!
      end
      ac_node.fail_link = 0
    end

    ac_node.depth = state[STATE_DEPTH]

    if  state.is_terminal then
      ac_node.magic_num_flags = 0x5b
    else
      ac_node.magic_num_flags = 0x5a
    end

    -- Populate the "input" and "goto_state" vector
    local input_vect = state[STATE_INPUT]
    local goto_func = state[STATE_GOTO]

    local ac_goto_num = input_vect[0]
    ac_node.goto_num = ac_goto_num

    local ac_goto_state = _ac_get_goto_vect(ac_node)
    tab_sort(input_vect)

    for i = 1, ac_goto_num do
      local c = input_vect[i]
      ac_node.input[i - 1] = c
      ac_goto_state[i - 1] = goto_func[c][STATE_OFST]
    end
  end

  local ac_root = ffi_cast(AC_NODE_ptr_t, buffer + root[STATE_OFST])
  ac_root.fail_link = 0
  root_charset = ffi_new("unsigned char[?]", 256)
  for i=1, 256 do
    root_charset[i-1] = 0
  end

  local gn = ac_root.goto_num
  for i=1, gn do
    root_charset[ac_root.input[i-1]] = 1
  end

  return ac_root, buffer, root_charset
end

-- ///////////////////////////////////////////////////////////////////////////
--
--        Module interface functions
--
-- ///////////////////////////////////////////////////////////////////////////
-- Construct a AC graph from a vector of strings)
function M.new(strs)
  local vect, vect_sz = _sm_build(strs)
  if vect then
    local ac_root, buffer = _convert(vect, vect_sz)
    collectgarbage()
    return { ac_root, buffer, root_charset}
  end
end

local function _state_goto(state, input, ac_buffer)
  local gn = state.goto_num

  -- Binary search the matching char
  local idx_l = 0
  local idx_r = gn - 1

  while idx_l <= idx_r do
    local mid = brshift(idx_l + idx_r, 1)
    local mid_c = state.input[mid]

    if mid_c > input then
      idx_r = mid - 1
    elseif mid_c < input then
      idx_l = mid + 1
    else
      local vect = _ac_get_goto_vect(state)
      state = ffi_cast(AC_NODE_ptr_t, ac_buffer + vect[mid])
      return state
    end
  end
end

-- The "graph" is a AC graph constructed by M.new(), and "str" is the string
-- to be matched. If a substring of "str" matches one of the strings represented
-- the AC graph, return the index-range of the sub-string. This function only
-- returns the first match; it will not return all maches.
--
-- E.g. The graph represents this set of string {"he", "she", "his", "her"}
-- and the string to be matched is "shis2". This function will return "2, 4" as
-- "shis2"[2:4] (i.e. "his") maches one of the string in the AC graph.
--
function M.match(graph, str)
  local root = graph[1]
  local buffer = graph[2]
  local root_charset = graph[3]
  local state = root
  local root_ofst = ffi_cast(uchar_ptr_t, root) - ffi_cast(uchar_ptr_t, buffer)
  local str_end = #str
  local str_idx = 1

  while str_idx <= str_end do
    local t = str_byte(str, str_idx)
    if root_charset[t] == 0 then
       str_idx = str_idx + 1
    else
       break;
    end
  end

  while str_idx <= str_end do
    local c = str_byte(str, str_idx)
    local new_state = _state_goto(state, c, buffer)

    --io.write(string.format("Input %c at loop\n", c))
    if new_state then
      state = new_state
      str_idx = str_idx + 1
    else
      local fail_link = state.fail_link
      if fail_link == root_ofst then
        state = root
        while str_idx <= str_end do
          local t = str_byte(str, str_idx)
          str_idx = str_idx + 1
          if root_charset[t] ~= 0 then
            state = _state_goto(state, t, buffer)
            break
          end
        end
      else
        -- Follow fail-link
        state = ffi_cast(AC_NODE_ptr_t, buffer + fail_link)
      end
    end

    if band(state.magic_num_flags, 1) == 1 then
      local cur_pos = str_idx - 1
      return cur_pos - state.depth + 1, cur_pos
    end
  end
end

return M
