local AC = require 'aho-corasick'
local string_sub = string.sub
local string_fmt = string.format
local fail_cnt = 0
local matching_cnt = 0

local function report(str, result)
  if result == true then
    io.write(string_fmt("Matching string '%s' pass\n", str))
  else
    fail_cnt = fail_cnt + 1
    io.write(string_fmt("Matching string '%s': fail\n", str))
  end
end

local function test_matching(ac_graph, strs)
  for str, match_sub_str in pairs(strs) do
    matching_cnt = matching_cnt + 1
    local b, e = AC.match(ac_graph, str)
    local r = (b and string_sub(str, b, e) == match_sub_str) and true or false
    report(str, r)
  end
end

local function test_not_matching(ac_graph, strs)
  local str_num = #strs;
  matching_cnt = matching_cnt + str_num

  for i = 1, str_num do
    local s = strs[i]
    local b = AC.match(ac_graph, s)
    if b then
        report(s, false)
    else
        report(s, true)
    end
  end
end

local function test(test_name, dict, match_strs, not_matching_strs)
  io.write(string_fmt("\n======= Testing test-suite: %s ========\n", test_name))

  local ac = AC.new(dict)
  test_matching(ac, match_strs)
  if not_matching_strs then
    print("")
    test_not_matching(ac, not_matching_strs)
  end
end

-- ////////////////////////////////////////////////////////////////
--
--      Testing cases starts from here
--
-- ////////////////////////////////////////////////////////////////

-- Testing cases from "Efficient String Matching: An Aid to Bibliographic
-- Search" (http://dl.acm.org/citation.cfm?id=360855).
--
do
  local dict = {"he", "she", "his", "her"}
  local match_str = {}

  match_str["he"] = "he"
  match_str["she"] = "she"
  match_str["his"] = "his"
  match_str["hers"] = "he" -- not "her"!
  match_str["ahe"] = "he"
  match_str["shhe"] = "he"
  match_str["shis2"] = "his"
  match_str["ahhe"] = "he"

  test("test1", dict, match_str, {"h2e", "se"})
end

-- Testing 
-- https://github.com/jgrahamc/aho-corasick-lua.git

io.write(string_fmt("\nTested %d cases, %d fails\n", matching_cnt, fail_cnt))
