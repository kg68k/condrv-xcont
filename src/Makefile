# Makefile for xcont

ifeq ($(notdir $(CURDIR)),src)
$(error do not execute make in src directory)
endif

SRCDIR_MK = ../srcdir.mk
SRC_DIR = ../src
-include $(SRCDIR_MK)

U8TOSJ = u8tosj
AS = has060
ASFLAGS = -w2 -c3
# -s__CRLF__
LD ?= hlk
LDFLAGS =
CV = cv
CP_P = cp -p

ifeq ($(findstring hlkx,$(LD)),hlkx)
USE_HLKX = true
endif

TARGET = xcont.r
DOCS = LICENSE xcont.txt
XCONT_ZIP = xcont.zip


.PHONY: all archive
.PRECIOUS: %.o

all: $(TARGET)


ifdef USE_HLKX
%.r: %.o
	$(LD) $(LDFLAGS) -r -o $@ $^
else
%.x: %.o
	$(LD) $(LDFLAGS) -o $@ $^
%.r: %.x
	$(CV) $< $@
endif

%.o: %.s
	$(AS) $(ASFLAGS) -o $@ $^


archive: $(XCONT_ZIP)

$(XCONT_ZIP): $(DOCS) $(TARGET)
	rm -f $@
	zip -9 $@ $^

LICENSE: $(SRC_DIR)/../LICENSE
	rm -f $@
	$(CP_P) $^ $@

%.txt: $(SRC_DIR)/../%.txt
	rm -f $@
	$(U8TOSJ) < $^ > $@


# EOF
