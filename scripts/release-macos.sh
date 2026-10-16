#!/bin/zsh
set -euo pipefail

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE}"

script_dir=${0:A:h}
project_dir=${script_dir:h}
archive_path="${project_dir}/MacApp/build/release/OpenChat.xcarchive"
app_path="${archive_path}/Products/Applications/OpenChat.app"
zip_path="${project_dir}/MacApp/build/release/OpenChat.zip"

xcodebuild archive \
  -project "${project_dir}/MacApp/OpenChat.xcodeproj" \
  -scheme OpenChat \
  -configuration Release \
  -archivePath "${archive_path}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION}" \
  DEVELOPMENT_TEAM="${APPLE_TEAM_ID}" \
  ENABLE_HARDENED_RUNTIME=YES

codesign --verify --deep --strict --verbose=2 "${app_path}"
ditto -c -k --keepParent "${app_path}" "${zip_path}"
xcrun notarytool submit "${zip_path}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${app_path}"
spctl --assess --type execute --verbose=2 "${app_path}"

print "Release ready: ${app_path}"
