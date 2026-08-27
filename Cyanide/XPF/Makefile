CC = clang

CHOMA_DYLIB_PATH ?= 0
CHOMA_PATH       ?= external/ChOma
CFLAGS            = -O2 -framework Foundation -I$(CHOMA_PATH)/include
CFLAGS_MACOS      = $(CFLAGS)
CFLAGS_IOS        = $(CFLAGS) -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -miphoneos-version-min=15.0 -arch arm64 -arch arm64e
CFLAGS_IOSSIM     = $(CFLAGS) -isysroot $(shell xcrun --sdk iphonesimulator --show-sdk-path) -mios-simulator-version-min=17.0 -arch arm64
LDFLAGS           = -lcompression

all: output/macos/libxpf.dylib output/ios/libxpf.dylib output/macos/xpf_test output/ios/xpf_test

ifneq ($(CHOMA_DYLIB_PATH), 0)
CHOMA_DEP = 
LDFLAGS  += -L$(CHOMA_DYLIB_PATH) -lchoma
else
CHOMA_DEP = $(CHOMA_PATH)/src/*.c
endif 

output/macos/libxpf.dylib: $(wildcard src/*.c) $(CHOMA_DEP)
	@mkdir -p $(shell dirname $@)
	$(CC) $(CFLAGS_MACOS) $(LDFLAGS) -dynamiclib -install_name @loader_path/libxpf.dylib -o $@ $^

output/ios/libxpf.dylib: $(wildcard src/*.c) $(CHOMA_DEP)
	@mkdir -p $(shell dirname $@)
	$(CC) $(CFLAGS_IOS) $(LDFLAGS) -dynamiclib -install_name @loader_path/libxpf.dylib -o $@ $^
# Sign the dylib. Prefer Apple codesign (always available on macOS / Xcode
# CI runners, generates a real code directory blob). Fall back to ldid if
# codesign is missing. ldid 2.1.5 on macOS 15 (Tahoe) arm64_tahoe bottle has
# produced an empty CODE_SIGNATURE superblob (cmd header only, 0 bytes of
# signature data) on the iOS 26 SDK dylib — that fails iOS link
# verification at runtime, which is why every exploit stage downstream
# (socket leak, KRW ready) reports controlSocket=rwSocket=-1 even though
# the binary otherwise looks identical to a locally-built one.
	codesign --force --sign - --timestamp=none $@ || ldid -S $@

output/iphonesimulator/libxpf.dylib: $(wildcard src/*.c) $(CHOMA_DEP)
	@mkdir -p $(shell dirname $@)
	$(CC) $(CFLAGS_IOSSIM) $(LDFLAGS) -dynamiclib -install_name @loader_path/libxpf.dylib -o $@ $^

output/macos/xpf_test: $(wildcard src/cli/*.c)
	@mkdir -p $(shell dirname $@)
	$(CC) $(CFLAGS_MACOS) $(LDFLAGS) -L$(shell dirname $@) -lxpf -o $@ $^

output/ios/xpf_test: $(wildcard src/cli/*.c)
	@mkdir -p $(shell dirname $@)
	$(CC) $(CFLAGS_IOS) $(LDFLAGS) -L$(shell dirname $@) -lxpf -o $@ $^
	@codesign --force --sign - --timestamp=none $@ || ldid -S $@

clean:
	@rm -rf output
