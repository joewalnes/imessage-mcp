# Build iMessageMCP.app in-place. The bundle lives next to the source —
# there is no separate install step. Grant Full Disk Access to the bundle
# at its checkout path; rebuilds preserve the grant.

APP_NAME   := iMessageMCP
BUNDLE_ID  := io.github.joewalnes.imessage-mcp
APP        := $(APP_NAME).app

BUILD_DIR  := .build
ICON_DIR   := $(BUILD_DIR)/icon
ICON       := $(ICON_DIR)/AppIcon.icns

LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

.PHONY: all swift-build test clean

all: $(APP)
	@echo ""
	@echo "Built $(CURDIR)/$(APP)"
	@echo ""
	@echo "Next:"
	@echo "  1. Grant Full Disk Access to:"
	@echo "       $(CURDIR)/$(APP)"
	@echo "     (System Settings -> Privacy & Security -> Full Disk Access)"
	@echo ""
	@echo "  2. Point your MCP client at:"
	@echo "       $(CURDIR)/$(APP)/Contents/MacOS/$(APP_NAME)"

$(APP): swift-build $(ICON) Resources/Info.plist
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c release --show-bin-path)/imessage-mcp" $(APP)/Contents/MacOS/$(APP_NAME)
	chmod +x $(APP)/Contents/MacOS/$(APP_NAME)
	cp $(ICON) $(APP)/Contents/Resources/AppIcon.icns
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign -f -s - --identifier "$(BUNDLE_ID)" $(APP)
	-[ -x "$(LSREGISTER)" ] && "$(LSREGISTER)" -f "$(CURDIR)/$(APP)" >/dev/null 2>&1

swift-build:
	swift build -c release

$(ICON): Scripts/make_icon.swift
	mkdir -p $(ICON_DIR)
	rm -rf $(ICON_DIR)/AppIcon.iconset
	swift Scripts/make_icon.swift $(ICON_DIR)/AppIcon.iconset >/dev/null
	iconutil -c icns $(ICON_DIR)/AppIcon.iconset -o $@

test:
	swift test

clean:
	rm -rf $(APP) $(BUILD_DIR)
	swift package clean 2>/dev/null || true
