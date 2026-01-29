#!/bin/sh

# This script fixes the missing CFBundleShortVersionString and CFBundleVersion in App.framework
# It should be run as a build phase in Xcode

echo "Fixing App.framework Info.plist..."

APP_FRAMEWORK_PLIST="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/App.framework/Info.plist"
RUNNER_PLIST="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"

if [ ! -f "$APP_FRAMEWORK_PLIST" ]; then
    echo "App.framework Info.plist not found at $APP_FRAMEWORK_PLIST"
    exit 0
fi

if [ ! -f "$RUNNER_PLIST" ]; then
    echo "Runner Info.plist not found at $RUNNER_PLIST"
    # Fallback to source plist if built one isn't ready (though it should be)
    RUNNER_PLIST="${SRCROOT}/Runner/Info.plist"
fi

# Function to read key from plist
read_plist_key() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null
}

# Function to write key to plist
write_plist_key() {
    local key="$1"
    local value="$2"
    local plist="$3"
    
    # Try to set first, if it fails (key doesn't exist), add it
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" 2>/dev/null
    if [ $? -ne 0 ]; then
        /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
    fi
}

# Get versions from Runner
SHORT_VERSION=$(read_plist_key "CFBundleShortVersionString" "$RUNNER_PLIST")
BUNDLE_VERSION=$(read_plist_key "CFBundleVersion" "$RUNNER_PLIST")

if [ -z "$SHORT_VERSION" ]; then
    echo "Could not find CFBundleShortVersionString in $RUNNER_PLIST"
    exit 1
fi

if [ -z "$BUNDLE_VERSION" ]; then
    echo "Could not find CFBundleVersion in $RUNNER_PLIST"
    exit 1
fi

echo "Injecting version $SHORT_VERSION ($BUNDLE_VERSION) into App.framework..."

write_plist_key "CFBundleShortVersionString" "$SHORT_VERSION" "$APP_FRAMEWORK_PLIST"
write_plist_key "CFBundleVersion" "$BUNDLE_VERSION" "$APP_FRAMEWORK_PLIST"

echo "Done."
