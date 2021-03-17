CC=g++
CFLAGS=
LDFLAGS=-lutil
PROGNAME=ndos-srv

src = $(wildcard *.cpp)
obj = $(src:.cpp=.o)
dep = $(obj:.o=.d)  # one dependency file for each source

# Recipe to build dependency files
%.d: %.cpp
	@$(CPP) $(CFLAGS) $< -MM -MT $(@:.d=.o) >$@

# Our main target
$(PROGNAME): $(obj)
	$(CC) -o $@ $^ $(LDFLAGS)

# include the dependency files
-include $(dep)

.PHONY: clean
clean:
	rm -f $(obj) $(PROGNAME) $(dep)

