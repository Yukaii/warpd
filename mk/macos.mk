.PHONY: rel all install clean

CFILES=$(shell find src/*.c)
OBJCFILES=$(filter-out src/platform/macos/url_handler.m, $(shell find src/platform/macos -name '*.m'))
OBJECTS=$(CFILES:.c=.o) $(OBJCFILES:.m=.o)

URL_HANDLER_APP=bin/warpd-url-handler.app
URL_HANDLER_EXEC=$(URL_HANDLER_APP)/Contents/MacOS/warpd-url-handler
URL_HANDLER_SRC=src/platform/macos/url_handler.m
URL_HANDLER_PLIST=files/warpd-url-handler/Info.plist

RELFLAGS=-Wl,-adhoc_codesign -framework cocoa -framework carbon

all: $(OBJECTS) url-handler
	-mkdir bin
	$(CC) -o bin/warpd $(OBJECTS) -framework cocoa -framework carbon
	./codesign/sign.sh
url-handler: $(URL_HANDLER_EXEC)

$(URL_HANDLER_EXEC): $(URL_HANDLER_SRC) $(URL_HANDLER_PLIST)
	mkdir -p $(URL_HANDLER_APP)/Contents/MacOS
	$(CC) -o $(URL_HANDLER_EXEC) $(URL_HANDLER_SRC) -framework cocoa
	cp $(URL_HANDLER_PLIST) $(URL_HANDLER_APP)/Contents/Info.plist
rel: clean
	$(CC) -o bin/warpd-arm $(CFILES) $(OBJCFILES) -target arm64-apple-macos $(CFLAGS) $(RELFLAGS)
	$(CC) -o bin/warpd-x86  $(CFILES) $(OBJCFILES) -target x86_64-apple-macos $(CFLAGS) $(RELFLAGS)
	lipo -create bin/warpd-arm bin/warpd-x86 -output bin/warpd && rm -r bin/warpd-*
	./codesign/sign.sh
	-rm -rf tmp dist
	mkdir tmp dist
	DESTDIR=tmp make install
	cd tmp && tar czvf ../dist/macos-$(VERSION).tar.gz $$(find . -type f)
	-rm -rf tmp
install: all
	mkdir -p $(DESTDIR)/usr/local/bin/ \
		$(DESTDIR)/usr/local/share/man/man1/ \
		$(DESTDIR)/usr/local/share/warpd \
		$(DESTDIR)/Library/LaunchAgents && \
	install -m644 files/warpd.1.gz $(DESTDIR)/usr/local/share/man/man1 && \
	install -m755 bin/warpd $(DESTDIR)/usr/local/bin/ && \
	cp -R $(URL_HANDLER_APP) $(DESTDIR)/usr/local/share/warpd/ && \
	install -m644 files/com.warpd.warpd.plist $(DESTDIR)/Library/LaunchAgents
uninstall:
	rm -f $(DESTDIR)/usr/local/share/man/man1/warpd.1.gz \
		$(DESTDIR)/usr/local/bin/warpd \
		$(DESTDIR)/Library/LaunchAgents/com.warpd.warpd.plist
	-rm -rf $(DESTDIR)/usr/local/share/warpd/warpd-url-handler.app
clean:
	-rm $(OBJECTS)
