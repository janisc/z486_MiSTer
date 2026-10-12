# libcosim86.a: 86Box's CPU core as the reference for the MiSTer sim's
# --cosim. The core is src/cpu of an 86Box checkout at ./86Box (branch
# z486-cosim; see UPSTREAM.md). libcosim86_stub.a stands in when there is no
# checkout: the simulator builds and --cosim reports that it is unavailable.

CC := gcc
BOX86 ?= 86Box
CPU := $(BOX86)/src/cpu
CFLAGS := -O2 -g -Wall -Wno-unused-variable -Wno-unused-function \
          -Wno-unused-but-set-variable -Wno-sign-compare \
          -Wno-parentheses -Wno-missing-braces \
          -Wno-implicit-function-declaration \
          -DOPS_286_386 -DUSE_NEW_DYNAREC \
          -I. -Iinclude -I$(CPU)
# The x87 (softfloat, 80-bit) is compiled in; cosim_set_fpu() selects it or
# the no-FPU ESC behaviour at run time.
CXX := g++
CXXFLAGS := -O2 -g -w -I. -Iinclude -I$(CPU) -I$(CPU)/softfloat3e

COSIM_SRCS := cosim86.c stubs.c x86seg_common.c x86seg.c x87.c x87_timings.c
COSIM_OBJS := $(COSIM_SRCS:%.c=obj/%.o)
# softfloat3e's own source list (C and C++ files).
SF_SRCS := $(shell sed -n '/add_library(softfloat3e/,/)/p' $(CPU)/softfloat3e/CMakeLists.txt | \
                   tr -s ' ()' '\n' | grep -E '\.(c|cc)$$')
SF_OBJS := $(addprefix obj/sf/,$(addsuffix .o,$(basename $(SF_SRCS))))
HDRS := $(wildcard *.h include/86box/*.h) $(wildcard $(CPU)/*.h)
vpath %.c $(CPU)
vpath %.cc $(CPU)/softfloat3e
vpath %.c $(CPU)/softfloat3e

.PHONY: all clean
all: libcosim86.a

obj/%.o: %.c $(HDRS)
	@mkdir -p obj
	$(CC) $(CFLAGS) -c -o $@ $<

obj/sf/%.o: %.cc
	@mkdir -p obj/sf
	$(CXX) $(CXXFLAGS) -c -o $@ $<

obj/sf/%.o: %.c
	@mkdir -p obj/sf
	$(CC) -O2 -g -w -I$(CPU)/softfloat3e -c -o $@ $<

libcosim86.a: $(COSIM_OBJS) $(SF_OBJS)
	ar rcs $@ $^

libcosim86_stub.a: cosim86_stub.c cosim86.h
	@mkdir -p obj
	$(CC) -O2 -Wall -I. -c -o obj/cosim86_stub.o cosim86_stub.c
	ar rcs $@ obj/cosim86_stub.o

clean:
	rm -rf obj libcosim86.a libcosim86_stub.a
