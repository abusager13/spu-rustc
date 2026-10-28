ifeq ($(strip $(PSL1GHT)),)
$(error Please set PSL1GHT to the installed PSL1GHT directory)
endif

include $(PSL1GHT)/ppu_rules

TARGET := spu-rustc-loader
OUTPUT := $(CURDIR)/$(TARGET)
RUST_TARGET := powerpc64-sony-ps3
RUST_TOOLCHAIN := nightly-2026-10-26
RUST_LIB := target/$(RUST_TARGET)/release/libspu_rustc_ppu_loader.a
BRIDGE_OBJ := build/bridge.o
CFLAGS := -O2 -Wall -mcpu=cell $(MACHDEP) $(INCLUDE)
LDFLAGS := $(MACHDEP)

.PHONY: all rust-library clean
all: $(OUTPUT).elf

rust-library:
	cargo +$(RUST_TOOLCHAIN) build -Z build-std=core --release \
		--target $(RUST_TARGET) --manifest-path Cargo.toml

$(BRIDGE_OBJ): source/bridge.c
	@mkdir -p build
	$(CC) $(CFLAGS) -I$(PSL1GHT)/ppu/include -c $< -o $@

$(OUTPUT).elf: $(BRIDGE_OBJ) rust-library
	$(CC) $(BRIDGE_OBJ) $(RUST_LIB) $(LDFLAGS) $(LIBPATHS) $(LIBS) -o $@

clean:
	rm -rf build target $(OUTPUT).elf
