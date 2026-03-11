APP_NAME = claude-usage-widget
SRC = ClaudeUsageWidget.swift
INSTALL_DIR = $(HOME)/.local/bin

.PHONY: build install uninstall clean

build:
	swiftc -O -o $(APP_NAME) $(SRC) -framework Cocoa -framework WebKit

install: build
	mkdir -p $(INSTALL_DIR)
	cp $(APP_NAME) $(INSTALL_DIR)/$(APP_NAME)
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME)"

uninstall:
	rm -f $(INSTALL_DIR)/$(APP_NAME)

clean:
	rm -f $(APP_NAME)

run: build
	@pkill -f $(APP_NAME) 2>/dev/null || true
	@sleep 0.3
	./$(APP_NAME) &
