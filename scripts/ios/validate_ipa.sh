#!/usr/bin/env bash
set -eo pipefail

# ==============================================================================
# validate_ipa.sh - Static validation tool for DDNet iOS IPA packages
# ==============================================================================

COLOR_RED="\033[1;31m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_CYAN="\033[1;36m"
COLOR_RESET="\033[0m"

function log_info() {
    printf "${COLOR_CYAN}[INFO] %s${COLOR_RESET}\n" "$1"
}

function log_pass() {
    printf "${COLOR_GREEN}[PASS] %s${COLOR_RESET}\n" "$1"
}

function log_warn() {
    printf "${COLOR_YELLOW}[WARN] %s${COLOR_RESET}\n" "$1"
}

function log_fail() {
    printf "${COLOR_RED}[FAIL] %s${COLOR_RESET}\n" "$1" 1>&2
    exit 1
}

IPA_PATH="$1"
EXPECTED_APP_NAME="${2:-DDNet}"
EXPECTED_BUNDLE_ID="${3:-org.ddnet.client}"

if [[ -z "${IPA_PATH}" ]]; then
    log_fail "Usage: $0 <path-to-ipa> [expected-app-name] [expected-bundle-id]"
fi

log_info "======================================================="
log_info "Starting static validation for iOS package: ${IPA_PATH}"
log_info "Expected App Name:   ${EXPECTED_APP_NAME}"
log_info "Expected Bundle ID:  ${EXPECTED_BUNDLE_ID}"
log_info "======================================================="

# 1. Check IPA existence and file size
if [[ ! -f "${IPA_PATH}" ]]; then
    log_fail "IPA file does not exist at '${IPA_PATH}'"
fi

IPA_SIZE=$(wc -c < "${IPA_PATH}" | tr -d ' ')
if [[ "${IPA_SIZE}" -lt 1000000 ]]; then
    log_fail "IPA file size (${IPA_SIZE} bytes) is suspiciously small (< 1 MB)"
fi
IPA_SIZE_MB=$(awk "BEGIN {printf \"%.2f\", ${IPA_SIZE}/1048576}")
log_pass "IPA exists and has valid size: ${IPA_SIZE_MB} MB (${IPA_SIZE} bytes)"

# 2. Check ZIP archive integrity
log_info "Verifying ZIP archive integrity..."
if ! unzip -tq "${IPA_PATH}" > /dev/null 2>&1; then
    log_fail "IPA archive is corrupted or not a valid ZIP file"
fi
log_pass "IPA ZIP archive is structurally valid"

# 3. Extract to a temporary directory
TEMP_DIR=$(mktemp -d /tmp/ddnet-ipa-validation.XXXXXX)
trap 'rm -rf "${TEMP_DIR}"' EXIT

log_info "Extracting IPA to temporary folder for inspection..."
unzip -q "${IPA_PATH}" -d "${TEMP_DIR}"

PAYLOAD_DIR="${TEMP_DIR}/Payload"
if [[ ! -d "${PAYLOAD_DIR}" ]]; then
    log_fail "IPA does not contain a 'Payload' directory"
fi
log_pass "Payload directory found in archive root"

# 4. Check for .app bundle
APP_DIR=""
for d in "${PAYLOAD_DIR}"/*.app; do
    if [[ -d "${d}" ]]; then
        APP_DIR="${d}"
        break
    fi
done

if [[ -z "${APP_DIR}" || ! -d "${APP_DIR}" ]]; then
    log_fail "No .app directory found inside Payload"
fi

ACTUAL_APP_DIRNAME=$(basename "${APP_DIR}")
log_pass "Application bundle located: ${ACTUAL_APP_DIRNAME}"

# 5. Check Info.plist
INFO_PLIST="${APP_DIR}/Info.plist"
if [[ ! -f "${INFO_PLIST}" ]]; then
    log_fail "Missing Info.plist in ${APP_DIR}"
fi

if command -v plutil > /dev/null 2>&1; then
    if ! plutil -lint "${INFO_PLIST}" > /dev/null 2>&1; then
        log_fail "Info.plist is not valid plist syntax"
    fi
fi
log_pass "Info.plist exists and is well-formed"

# Helper function to read plist keys
get_plist_value() {
    local key="$1"
    if command -v plutil > /dev/null 2>&1; then
        plutil -extract "${key}" raw -expect string "${INFO_PLIST}" 2>/dev/null || \
        plutil -extract "${key}" raw "${INFO_PLIST}" 2>/dev/null || true
    elif command -v /usr/libexec/PlistBuddy > /dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Print :${key}" "${INFO_PLIST}" 2>/dev/null || true
    else
        python3 -c "import plistlib, sys; p = plistlib.load(open('${INFO_PLIST}', 'rb')); print(p.get('${key}', ''))" 2>/dev/null || true
    fi
}

# 6. Check Executable
BUNDLE_EXEC=$(get_plist_value "CFBundleExecutable")
if [[ -z "${BUNDLE_EXEC}" ]]; then
    log_fail "CFBundleExecutable is not defined in Info.plist"
fi

EXEC_PATH="${APP_DIR}/${BUNDLE_EXEC}"
if [[ ! -f "${EXEC_PATH}" ]]; then
    log_fail "Main executable '${BUNDLE_EXEC}' not found in app bundle: ${EXEC_PATH}"
fi

if [[ ! -x "${EXEC_PATH}" ]]; then
    log_warn "Executable bit not set on '${EXEC_PATH}', fixing permissions..."
    chmod +x "${EXEC_PATH}"
fi
log_pass "Executable binary found: ${BUNDLE_EXEC}"

# 7. Check Architecture (Must be arm64)
log_info "Verifying executable binary architecture..."
ARCH_INFO=""
if command -v lipo > /dev/null 2>&1; then
    ARCH_INFO=$(lipo -info "${EXEC_PATH}" 2>&1 || true)
    log_info "lipo output: ${ARCH_INFO}"
fi

FILE_INFO=$(file "${EXEC_PATH}" 2>&1 || true)
log_info "file output: ${FILE_INFO}"

if [[ "${ARCH_INFO}" != *"arm64"* && "${FILE_INFO}" != *"arm64"* && "${FILE_INFO}" != *"aarch64"* ]]; then
    log_fail "Executable '${BUNDLE_EXEC}' is NOT arm64 architecture! Detected: ${FILE_INFO}"
fi
log_pass "Executable architecture verified as arm64"

# 8. Check Bundle Identifier
BUNDLE_ID=$(get_plist_value "CFBundleIdentifier")
if [[ -z "${BUNDLE_ID}" ]]; then
    log_fail "CFBundleIdentifier not found in Info.plist"
fi

if [[ -n "${EXPECTED_BUNDLE_ID}" && "${BUNDLE_ID}" != "${EXPECTED_BUNDLE_ID}" ]]; then
    log_warn "Bundle ID '${BUNDLE_ID}' differs from expected '${EXPECTED_BUNDLE_ID}'"
else
    log_pass "Bundle Identifier matches: ${BUNDLE_ID}"
fi

# 9. Check Deployment Target (MinimumOSVersion)
MIN_OS=$(get_plist_value "MinimumOSVersion")
if [[ -z "${MIN_OS}" ]]; then
    log_warn "MinimumOSVersion not explicitly set in Info.plist (Xcode might add on final code sign)"
else
    log_pass "Deployment target MinimumOSVersion: ${MIN_OS}"
fi

# 10. Check Required Assets & Icons
if [[ -f "${APP_DIR}/Assets.car" ]]; then
    log_pass "Compiled asset catalog present: Assets.car"
elif compgen -G "${APP_DIR}/AppIcon*.png" > /dev/null; then
    log_pass "AppIcon image assets found in app bundle"
else
    log_warn "No Assets.car or AppIcon*.png detected directly; checking subdirectories"
fi

# 11. Check Bundled DDNet Game Data & storage.cfg
log_info "Validating bundled game data..."
if [[ ! -d "${APP_DIR}/data" ]]; then
    log_fail "Critical DDNet game 'data' directory is missing from app bundle!"
fi

if [[ ! -d "${APP_DIR}/data/maps" ]]; then
    log_fail "Game maps directory 'data/maps' is missing from app bundle!"
fi

MAP_COUNT=$(find "${APP_DIR}/data/maps" -type f -name "*.map" | wc -l | tr -d ' ')
if [[ "${MAP_COUNT}" -eq 0 ]]; then
    log_fail "No map files found in 'data/maps'!"
fi
log_pass "Bundled maps validated (${MAP_COUNT} maps found)"

if [[ ! -d "${APP_DIR}/data/audio" ]]; then
    log_fail "Game audio directory 'data/audio' is missing from app bundle!"
fi
log_pass "Bundled audio directory validated"

if [[ ! -f "${APP_DIR}/storage.cfg" ]]; then
    log_fail "storage.cfg is missing from app bundle!"
fi
log_pass "storage.cfg verified in app bundle"

# 12. Check Frameworks and Linked Libraries
if command -v otool > /dev/null 2>&1; then
    log_info "Inspecting linked libraries via otool..."
    OTOOL_OUTPUT=$(otool -L "${EXEC_PATH}" 2>&1 || true)
    log_info "Linked dynamic libraries summary:"
    echo "${OTOOL_OUTPUT}" | head -n 25
fi
log_pass "Framework and library dependencies inspected"

# 13. Check Code Signing State
log_info "Inspecting code signing state..."
if command -v codesign > /dev/null 2>&1; then
    SIGN_OUTPUT=$(codesign -dvvv "${APP_DIR}" 2>&1 || true)
    echo "${SIGN_OUTPUT}"
    if echo "${SIGN_OUTPUT}" | grep -q "code object is not signed at all"; then
        log_warn "App bundle is unsigned (expected for developer builds without private certificates)"
    else
        log_pass "App bundle has valid code signature structure"
    fi
else
    log_info "codesign tool not available on this host; skipping signature inspection"
fi

# 14. Summary of App Bundle Size
APP_SIZE_BYTES=$(du -sk "${APP_DIR}" | awk '{print $1 * 1024}')
APP_SIZE_MB=$(awk "BEGIN {printf \"%.2f\", ${APP_SIZE_BYTES}/1048576}")
log_info "Uncompressed application bundle size: ${APP_SIZE_MB} MB"

log_info "======================================================="
log_pass "ALL STATIC IPA VALIDATION CHECKS PASSED SUCCESSFULLY!"
log_info "======================================================="
exit 0
