CC ?= cc

CPPFLAGS := -Iinclude
CFLAGS := -std=c11 -Wall -Wextra -Werror -pedantic -pthread
LDFLAGS :=
LDLIBS :=

TARGET := bin/pbnfc
SOURCES := src/main.c
OBJECTS := $(patsubst src/%.c,build/%.o,$(SOURCES))
DEPFILES := $(OBJECTS:.o=.d)

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJECTS) | bin
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

build/%.o: src/%.c | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

bin build:
	mkdir -p $@

-include $(DEPFILES)

clean:
	rm -rf build bin
