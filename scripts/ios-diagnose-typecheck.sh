#!/bin/bash
# TEMPORARY build diagnostics helper (not part of the app).
#
# Type-checks the iOS target's Swift sources with the same toolchain Xcode uses and
# republishes every `error:` it finds as a GitHub Actions annotation, so the compiler
# messages can be read through the Checks API when the raw job log is not reachable.
#
# `|| true` is used at the call site: this never changes build outcome.

set -u

SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SOURCES="$(find "$SRCROOT/EchoMusic" -name '*.swift' | sort)"
DIAG_LOG="${TMPDIR:-/tmp}/echo-ios-typecheck.log"

# Keep the flags aligned with ios/project.yml: Swift 5.9+, iOS 17 minimum, and
# `-parse-as-library` so `@main` is accepted in a whole-module type check.
# shellcheck disable=SC2086
xcrun swiftc \
  -typecheck \
  -sdk "$SDK_PATH" \
  -target arm64-apple-ios17.0-simulator \
  -module-name Echo_Music \
  -parse-as-library \
  -swift-version 5 \
  -suppress-warnings \
  $SOURCES >"$DIAG_LOG" 2>&1

STATUS=$?
echo "diagnostics: swiftc -typecheck exit=${STATUS}"

count=0
while IFS= read -r line; do
  case "$line" in
    *": error:"*) ;;
    *) continue ;;
  esac

  path="${line%%:*}"
  rest="${line#*:}"
  lineno="${rest%%:*}"
  message="${line#*: error:}"
  message="${message#"${message%%[![:space:]]*}"}"

  # Make the path relative to the repository root so GitHub links the annotation.
  rel="${path##*Echo-Music/}"
  [ "$rel" = "$path" ] && rel="$path"
  case "$lineno" in (*[!0-9]*|"") lineno=1 ;; esac

  # Escape the characters that have meaning in a workflow command.
  esc_message="${message//%/%25}"
  esc_message="${esc_message//$'\r'/}"
  rel="${rel//%/%25}"
  rel="${rel//,/%2C}"

  printf '::error file=%s,line=%s,title=Swift error::%s\n' "$rel" "$lineno" "$esc_message"
  count=$((count + 1))
  [ "$count" -ge 20 ] && break
done < "$DIAG_LOG"

if [ "$count" -eq 0 ] && [ "$STATUS" -ne 0 ]; then
  summary="$(grep -E "error|fatal" "$DIAG_LOG" | head -3 | tr '\n' ' ')"
  printf '::error title=Swift typecheck (no line diagnostics)::%s\n' "${summary//%/%25}"
fi

exit 0
