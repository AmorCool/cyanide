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
# Sign the dylib. ldid 2.1.5 from the macos-15 (Tahoe) arm64_tahoe bottle
# produces an empty CODE_SIGNATURE superblob (cmd header only, 0 bytes of
# signature data) when signing an iOS 26 SDK fat arm64/arm64e dylib. That
# fails iOS link verification at runtime, which is why every exploit stage
# downstream (socket leak, KRW ready, RemoteCall to SpringBoard) reports
# controlSocket=rwSocket=-1 even though the binary otherwise looks
# identical to a locally-built one.
#
# Try Apple codesign first. Use --force -s - (ad-hoc) without
# --timestamp=none, which is not a recognized option in macOS 15
# codesign and was making it exit non-zero, falling through to ldid.
# Final fallback to ldid for older toolchains.
	codesign --force --sign - $@ || ( codesign --force -s - $@ ) || ldid -S $@

output/iphonesimulator/libxpf.dylib: $(wildcard src/*.c) $(CHOMA_DEP)
	@mkdir -p $(shell dirname $@)
	$(CC) $(CFLAGS_IOSSIM) $(LDFLAGS) -dynamiclib -install_name @loader_path/libxpf.dylib -o $@ $^

output/macos/xpf_test: $(wildcard src/cli/*.c)
	@mkdir -p $(shell dirname $@)
	$(CC) $(CFLAGS_MACOS) $(LDFLAGS) -L$(shell dirname $@) -lxpf -o $@ $^

output/ios/xpf_test: $(wildcard src/cli/*.c)
	@mkdir -p $(shell dirname $@)
	$(CC) $(CFLAGS_IOS) $(LDFLAGS) -L$(shell dirname $@) -lxpf -o $@ $^
	@codesign --force --sign - $@ || ( codesign --force -s - $@ ) || ldid -S $@

clean:
	@rm -rf output
