CC=g++
CFLAGS=
LIBS=
PROGNAME=ndos-srv

src = $(wildcard *.cpp)
obj = $(src:.cpp=.o)
dep = $(obj:.o=.d)  # one dependency file for each source

%.d: %.cpp
	@$(CPP) $(CFLAGS) $< -MM -MT $(@:.d=.o) >$@

 
$(PROGNAME): $(obj)
	$(CC) -o $@ $^ $(LDFLAGS)


.PHONY: clean
clean:
	rm -f $(obj) $(PROGNAME)

.PHONY: cleandep
cleandep:
	rm -f $(dep)

