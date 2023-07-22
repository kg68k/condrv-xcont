# Makefile for xcont

ifeq ($(notdir $(CURDIR)),src)
$(error do not execute make in src directory)
endif

AS	= has060
#ASFLAGS= -s__CRLF__
LD	= hlk
LDFLAGS	= -r

SRCS	= xcont.s
DOCS	= xcont.txt

SRC_ZIP	 = src.zip
XCONT_ZIP = xcont.zip
ARCS	= $(SRC_ZIP) $(COND_ZIP)

all: xcont.r

%.r: %.o
	$(LD) $(LDFLAGS) -o $@ $^

%.o: %.s
	$(AS) $(ASFLAGS) -o $@ $^


$(SRC_ZIP): $(SRCS) Makefile
	rm -f $@
	zip -9 $@ $^

$(XCONT_ZIP): $(SRC_ZIP) $(DOCS) xcont.r
	rm -f $@
	zip -9 $@ $^

# EOF
