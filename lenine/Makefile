PREFIX  ?= /
SBINDIR := $(PREFIX)/sbin
BIN     := lenine

.PHONY: all clean install

all: $(BIN)

$(BIN): *.go go.mod
	CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o $(BIN) .

install: $(BIN)
	install -Dm755 $(BIN) $(DESTDIR)$(SBINDIR)/$(BIN)

clean:
	rm -f $(BIN)
