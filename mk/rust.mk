RUST_DIR = ui
RUST_TARGET = $(RUST_DIR)/target/release/warpd-ui
RUST_SOURCES = $(shell find $(RUST_DIR)/src -name '*.rs')

$(RUST_TARGET): $(RUST_DIR)/Cargo.toml $(RUST_SOURCES)
	cd $(RUST_DIR) && cargo build --release

rust: $(RUST_TARGET)

clean-rust:
	cd $(RUST_DIR) && cargo clean

install-rust: $(RUST_TARGET)
	install -m 755 $(RUST_TARGET) $(PREFIX)/bin/warpd-ui

test-rust:
	cd $(RUST_DIR) && cargo test

.PHONY: rust clean-rust install-rust test-rust
