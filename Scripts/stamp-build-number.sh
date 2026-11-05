#!/bin/sh
set -eu
number=$(cat "$DERIVED_FILE_DIR/IntoEnglishBuildNumber.txt")
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.0.0" "$TARGET_BUILD_DIR/$INFOPLIST_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $number" "$TARGET_BUILD_DIR/$INFOPLIST_PATH"
