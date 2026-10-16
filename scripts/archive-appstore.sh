#!/bin/zsh
set -euo pipefail
# App Store archive — run after setting up App Store Connect record.
# Requires: Apple Developer Program membership, App Store Connect API key or Xcode signing.
script_dir=${0:A:h}
project_dir=${script_dir:h}
archive_path="${project_dir}/MacApp/build/appstore/OpenChat.xcarchive"

xcodebuild archive \
  -project "${project_dir}/MacApp/OpenChat.xcodeproj" \
  -scheme OpenChat \
  -configuration Release \
  -archivePath "${archive_path}"

echo "Archive ready: ${archive_path}"
echo "Upload via: Xcode > Window > Organizer, or:"
echo "  xcrun altool --upload-app -f <ipa> --type macos -u <apple-id>"
