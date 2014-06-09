local ac = require "ahocorasick"

local ac_create = ac.create
local ac_match = ac.match
local string_fmt = string.format
local string_sub = string.sub

local function mytest(testname, dict, match, notmatch)
    print(">Testing ", testname)
    
    io.write(string_fmt("Dictionary: "));
    for i=1, #dict do
       io.write(string_fmt("%s, ", dict[i]))
    end
    print ""

    local ac_inst = ac_create(dict);
    for i=1, #match do
        local str = match[i][1]
        local substr = match[i][2]
        io.write(string_fmt("Matching %s, ", str))
        local b, e = ac_match(ac_inst, str)
        if b and e and (string_sub(str, b+1, e+1) == substr) then
            print "pass"
        else 
            print "fail"
        end
    end
end

mytest("test1",
       {"he", "she", "his", "her"},
       {{"he", "he"}, {"she", "she"}, {"his", "his"}, {"hers", "he"},
        {"ahe", "he"}, {"shhe", "he"}, {"shis2", "his"}, {"ahhe", "he"}})
