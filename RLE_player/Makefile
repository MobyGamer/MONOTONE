CC=gcc
LD=$(CC)

CFLAGS=-Wall
LDFLAGS=-lm

PROGS=pitcomp

.PHONY : clean

all: $(PROGS)

pitcomp: pitcomp.o
	$(LD) $^ $(LDFLAGS) -o $@

clean:
	rm -vf *.o $(PROGS)
