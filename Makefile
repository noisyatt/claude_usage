APP_NAME = claude-usage-widget
BUNDLE_NAME = Claude Usage
SRC = ClaudeUsageWidget.swift
INSTALL_DIR = $(HOME)/.local/bin
APP_BUNDLE = $(BUNDLE_NAME).app

.PHONY: build app install uninstall clean run

build:
	swiftc -O -o $(APP_NAME) $(SRC) -framework Cocoa -framework WebKit

app: build icon
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp $(APP_NAME) "$(APP_BUNDLE)/Contents/MacOS/$(BUNDLE_NAME)"
	cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	@echo "Built $(APP_BUNDLE)"

icon: scripts/gen_icon.swift
	@if [ ! -f AppIcon.icns ]; then \
		swiftc -O scripts/gen_icon.swift -framework Cocoa -o /tmp/gen_icon && /tmp/gen_icon && \
		iconutil --convert icns /tmp/AppIcon.iconset -o AppIcon.icns && \
		rm -rf /tmp/AppIcon.iconset /tmp/gen_icon; \
	fi

install: build
	mkdir -p $(INSTALL_DIR)
	cp $(APP_NAME) $(INSTALL_DIR)/$(APP_NAME)
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME)"

install-app: app
	cp -R "$(APP_BUNDLE)" /Applications/
	@echo "Installed to /Applications/$(APP_BUNDLE)"

uninstall:
	rm -f $(INSTALL_DIR)/$(APP_NAME)
	rm -rf "/Applications/$(APP_BUNDLE)"

clean:
	rm -f $(APP_NAME) AppIcon.icns
	rm -rf "$(APP_BUNDLE)"

run: build
	@pkill -f "$(APP_NAME)" 2>/dev/null || true
	@sleep 0.3
	./$(APP_NAME) &
