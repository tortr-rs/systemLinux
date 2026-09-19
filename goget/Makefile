PREFIX  ?= /usr/local
BINDIR  := $(PREFIX)/bin
BIN     := goget

.PHONY: all clean install

all: $(BIN)

$(BIN): *.go go.mod
	CGO_ENABLED=0 go build -o $(BIN) .

install: $(BIN)
	install -Dm755 $(BIN) $(BINDIR)/$(BIN)

clean:
	rm -f $(BIN)
