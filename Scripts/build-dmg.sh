#!/bin/bash
set -e

# ============================================================================
# Interviewer - Build, Sign, Notarize, and Create DMG
# ============================================================================
#
# Prerequisites:
# 1. Developer ID Application certificate installed in Keychain
# 2. App-specific password for notarization (from appleid.apple.com)
# 3. Store credentials in Keychain:
#    xcrun notarytool store-credentials "Interviewer-Notarization" \
#      --apple-id "your-apple-id@example.com" \
#      --team-id "28FC5D45XH" \
#      --password "your-app-specific-password"
#
# Usage: ./Scripts/build-dmg.sh
# ============================================================================

# Configuration
APP_NAME="Interviewer"
BUNDLE_ID="com.thephotomap.Interviewer"
TEAM_ID="28FC5D45XH"
SIGNING_IDENTITY="Developer ID Application: The Photo Map LLC (28FC5D45XH)"
NOTARIZATION_PROFILE="Interviewer-Notarization"

# Paths
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/Export"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_step() {
    echo -e "${GREEN}==>${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

echo_error() {
    echo -e "${RED}Error:${NC} $1"
    exit 1
}

# Check for required tools
check_requirements() {
    echo_step "Checking requirements..."

    if ! command -v xcodebuild &> /dev/null; then
        echo_error "xcodebuild not found. Please install Xcode."
    fi

    if ! command -v xcrun &> /dev/null; then
        echo_error "xcrun not found. Please install Xcode Command Line Tools."
    fi

    # Check for signing identity
    if ! security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
        echo_error "Signing identity not found: $SIGNING_IDENTITY"
    fi

    echo "  ✓ All requirements met"
}

# Clean previous builds
clean() {
    echo_step "Cleaning previous builds..."
    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"
    echo "  ✓ Clean complete"
}

# Build and archive
build() {
    echo_step "Building and archiving..."

    cd "${PROJECT_DIR}"

    xcodebuild archive \
        -project "${APP_NAME}.xcodeproj" \
        -scheme "${APP_NAME}" \
        -configuration Release \
        -archivePath "${ARCHIVE_PATH}" \
        CODE_SIGN_IDENTITY="${SIGNING_IDENTITY}" \
        DEVELOPMENT_TEAM="${TEAM_ID}" \
        CODE_SIGN_STYLE=Manual \
        PROVISIONING_PROFILE_SPECIFIER="" \
        2>&1 | tee "${BUILD_DIR}/archive.log"

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo_error "Archive failed. Check ${BUILD_DIR}/archive.log"
    fi

    echo "  ✓ Archive created at ${ARCHIVE_PATH}"
}

# Export the app
export_app() {
    echo_step "Exporting app..."

    # Create export options plist
    cat > "${BUILD_DIR}/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
EOF

    xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "${EXPORT_PATH}" \
        -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist" \
        | xcpretty || xcodebuild -exportArchive \
            -archivePath "${ARCHIVE_PATH}" \
            -exportPath "${EXPORT_PATH}" \
            -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist"

    echo "  ✓ App exported to ${APP_PATH}"
}

# Notarize the app
notarize() {
    echo_step "Notarizing app (this may take a few minutes)..."

    # Create a zip for notarization
    NOTARIZE_ZIP="${BUILD_DIR}/${APP_NAME}-notarize.zip"
    ditto -c -k --keepParent "${APP_PATH}" "${NOTARIZE_ZIP}"

    # Submit for notarization
    xcrun notarytool submit "${NOTARIZE_ZIP}" \
        --keychain-profile "${NOTARIZATION_PROFILE}" \
        --wait

    # Staple the notarization ticket
    echo_step "Stapling notarization ticket..."
    xcrun stapler staple "${APP_PATH}"

    # Clean up
    rm -f "${NOTARIZE_ZIP}"

    echo "  ✓ Notarization complete"
}

# Create DMG
create_dmg() {
    echo_step "Creating DMG..."

    # Remove old DMG if exists
    rm -f "${DMG_PATH}"

    # Create a temporary DMG folder
    DMG_TEMP="${BUILD_DIR}/dmg-temp"
    rm -rf "${DMG_TEMP}"
    mkdir -p "${DMG_TEMP}"

    # Copy app to temp folder
    cp -R "${APP_PATH}" "${DMG_TEMP}/"

    # Create symlink to Applications
    ln -s /Applications "${DMG_TEMP}/Applications"

    # Create the DMG
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "${DMG_TEMP}" \
        -ov -format UDZO \
        "${DMG_PATH}"

    # Sign the DMG
    codesign --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"

    # Notarize the DMG
    echo_step "Notarizing DMG..."
    xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "${NOTARIZATION_PROFILE}" \
        --wait

    xcrun stapler staple "${DMG_PATH}"

    # Clean up
    rm -rf "${DMG_TEMP}"

    echo "  ✓ DMG created at ${DMG_PATH}"
}

# Verify the build
verify() {
    echo_step "Verifying signatures..."

    # Verify app signature
    codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

    # Verify notarization
    spctl --assess --type exec --verbose "${APP_PATH}"

    # Verify DMG
    codesign --verify --verbose=2 "${DMG_PATH}"
    spctl --assess --type open --context context:primary-signature --verbose "${DMG_PATH}"

    echo "  ✓ All signatures valid"
}

# Main
main() {
    echo ""
    echo "================================================"
    echo "  ${APP_NAME} - Build & Distribution"
    echo "================================================"
    echo ""

    check_requirements
    clean
    build
    export_app
    notarize
    create_dmg
    verify

    echo ""
    echo "================================================"
    echo -e "  ${GREEN}Build complete!${NC}"
    echo "  DMG: ${DMG_PATH}"
    echo "================================================"
    echo ""
}

main "$@"
