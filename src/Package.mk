# Makefile for xcont (create archive file)
#  usage: mkdir pkgtmp; make -C pkgtmp -f ../Package.mk

SRCDIR_MK = ../../srcdir.mk
SRC_DIR = ../../src
-include $(SRCDIR_MK)

ROOT_DIR = $(SRC_DIR)/..
BUILD_DIR = ..

CP_P = cp -p
U8TOSJ = u8tosj

DOCS = CHANGELOG.txt LICENSE xcont.txt
PROGRAM = xcont.r

FILES = $(DOCS) $(PROGRAM)
XCONT_ZIP = $(BUILD_DIR)/xcont.zip


.PHONY: all

all: $(XCONT_ZIP)

CHANGELOG.txt: $(ROOT_DIR)/CHANGELOG.md
	$(U8TOSJ) < $^ >! $@

%.txt: $(ROOT_DIR)/%.txt
	$(U8TOSJ) < $^ >! $@

LICENSE: $(ROOT_DIR)/LICENSE
	rm -f $@
	$(CP_P) $^ $@

$(PROGRAM): $(BUILD_DIR)/$(PROGRAM)
	rm -f $@
	$(CP_P) $^ $@

$(XCONT_ZIP): $(FILES)
	rm -f $@
	zip -9 $@ $^


# EOF
