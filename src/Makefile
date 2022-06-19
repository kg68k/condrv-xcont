# Makefile for xcont

AS	= has
#ASFLAGS= -s__CRLF__
LD	= hlk
LDFLAGS	= -r

all : xcont.r

%.r: %.o
	$(LD) $(LDFLAGS) -o $@ $^

%.o: %.s
	$(AS) $(ASFLAGS) -o $@ $^

# EOF
