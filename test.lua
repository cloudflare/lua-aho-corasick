local AC = require 'aho-corasick'

local dict = {"he", "she", "his", "her"}

local graph = AC.new(dict)
local tab2 = {"ahe", "shis2"}

for i=1, #tab2 do
    local str = tab2[i]
    local b, e = AC.match(graph, str)
    if b then
        io.write(string.format("%s [%d:%d] match\n", str, b, e))
    else
        io.write(string.format("%s, no match\n"))
    end
end
