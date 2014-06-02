aho-corasick-lua
================

  Lua implementation of the Aho-Corasick (AC) string matching algorithm
(http://dl.acm.org/citation.cfm?id=360855).

  For efficiency reasons, the output() function doesn't return a set of
matching strings, instead, it returns no more than one matching string.

  This is an example illustrating how our implementation is different from
the standard AC algorithm due to the different semantics of output() function:
Suppose the AC-graph/dictionary represent a set of strings
{..., "she", "he", ... }, and the string to be matched is "...123she456...".
The stardard AC algorithm will report the given string matches both "she" and
"he". However, our implementation reports only one match (either "she" or "he").

  It's not difficult to get rid of this limitation. But I don't know for sure
if it's worth doing that at the cost of additional memory, computation and
complexity.

  !!!NOTE!!!: If the dictionary is small, say having less than 50 entries,
LUA implementation could be significantly slower than the brute-force approach
by matching the specified string against all strings in the dictionary via
string.find().
