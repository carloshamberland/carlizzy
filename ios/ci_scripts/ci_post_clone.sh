#!/bin/sh

# Fail this script if any subcommand fails
set -e

echo "Installing Flutter..."

# Clone Flutter SDK
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

echo "Running flutter pub get..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter pub get

echo "Installing CocoaPods dependencies..."
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
pod install

echo "Post-clone script completed successfully!"
