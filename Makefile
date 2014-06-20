#############################################################################
#
#           Binaries we are going to build
#
#############################################################################
#
C_SO_NAME = libac.so
LUA_SO_NAME = ahocorasick.so
TEST = ac_test

#############################################################################
#
#           Compile and link flags
#
#############################################################################

PREFIX = /usr/local
LUA_VERSION := 5.1
LUA_INCLUDE_DIR := /usr/include/lua$(LUA_VERSION)
SO_TARGET_DIR := /usr/local/lib/lua/$(LUA_VERSION)
LUA_TARGET_DIR := /usr/local/share/lua/$(LUA_VERSION)

# Available directives:
# -DDEBUG : Turn on debugging support
# -DUSE_SLOW_VER : Use the "slow" version of the Aho-Corasink implmentation.
#
CFLAGS = -msse2 -msse3 -msse4.1 -O3
COMMON_FLAGS = -fvisibility=hidden -Wall $(CFLAGS)

SO_CXXFLAGS = $(COMMON_FLAGS) -fPIC
NON_SO_CXXFLAGS = $(COMMON_FLAGS)
SO_LFLAGS = $(COMMON_FLAGS)
NON_SO_FLAGS = $(COMMON_FLAGS)

#############################################################################
#
#           Make rules
#
#############################################################################
#
.PHONY = all clean test
all : $(C_SO_NAME) $(LUA_SO_NAME) $(TEST)
	-cat *.d > dep.txt

-include dep.txt

COMMON_CXX_SRC = ac_fast.cxx ac_slow.cxx
C_SO_CXX_SRC = ac.cxx
LUA_SO_CXX_SRC = ac_lua.cxx

COMMON_OBJ = ${COMMON_CXX_SRC:.cxx=.o}
C_SO_OBJ = ${C_SO_CXX_SRC:.cxx=.o}
LUA_SO_OBJ = ${LUA_SO_CXX_SRC:.cxx=.o}

# Static-Pattern-Rules for the objects comprising the shared objects.
$(COMMON_OBJ) $(C_SO_OBJ) : %.o : %.cxx
	$(CXX) $< -c $(SO_CXXFLAGS) -MMD

# Static-Pattern-Rules for aho-corasick.so's interface object files, which
# need to call LUA C-API.
$(LUA_SO_OBJ) : %.o : %.cxx
	$(CXX) $< -c $(SO_CXXFLAGS) -I$(LUA_INCLUDE_DIR) -MMD

# Build libac.so
$(C_SO_NAME) : $(COMMON_OBJ) $(C_SO_OBJ)
	$(CXX) $+ -shared -Wl,-soname=$(C_SO_NAME) $(SO_LFLAGS) -o $@

# Build aho-corasick.so
$(LUA_SO_NAME) : $(COMMON_OBJ) $(LUA_SO_OBJ)
	$(CXX) $+ -shared -Wl,-soname=$(LUA_SO_NAME) $(SO_LFLAGS) -o $@

# Build ac_test
ac_test.o : ac_test.cxx
	$(CXX) $< -c $(NON_SO_CXXFLAGS) -MMD

$(TEST) : $(C_SO_NAME) ac_test.o
	$(CXX) ac_test.o $(C_SO_NAME) -o $@

#############################################################################
#
#           Testing stuff
#
#############################################################################
#
test:$(TEST) testinput/text.tar
	./$(TEST) testinput/*

testinput/text.tar:
	echo "download testing files (gcc tarball)..."
	[ ! -d testinput ] && mkdir testinput  && \
	cd testinput && \
    curl ftp://ftp.gnu.org/gnu/gcc/gcc-1.42.tar.gz -o text.tar.gz 2>/dev/null \
    && gzip -d text.tar.gz

#############################################################################
#
#           Misc
#
#############################################################################
#
clean :
	-rm -f *.o *.d dep.txt $(TEST) $(C_SO_NAME) $(LUA_SO_NAME) $(TEST)

install:
	install -D -m 755 $(C_SO_NAME) $(SO_TARGET_DIR)/$(C_SO_NAME)
	install -D -m 755 $(LUA_SO_NAME) $(SO_TARGET_DIR)/$(LUA_SO_NAME)
	install -D -m 664 load_ac.lua $(LUA_TARGET_DIR)/load_ac.lua

