#!/bin/bash
# TEMPORARY diagnostics helper (delete together with the matching block in
# ios/project.yml). Never fails the build: the caller wraps it in `|| true`.
#
# Runs the same frontend work Xcode does for this target — full-module type check plus
# module emission, for both simulator arch slices — and reports what it finds through
# Actions annotations and (if the job token allows) a PR comment, because the raw job
# log is not always fetchable.

set -u

SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/echo-diag.XXXXXX")"
SOURCES="$WORK/sources.txt"
REPORT="$WORK/report.txt"
find "$SRCROOT/EchoMusic" -name '*.swift' | sort >"$SOURCES"

{
  echo "pre-build script phase ran: yes"
  echo "source files: $(wc -l <"$SOURCES" | tr -d ' ')"
  echo "xcode: $(xcodebuild -version 2>&1 | tr '\n' ' ')"
} >"$REPORT"

annotate() { printf '::error title=%s::%s\n' "$1" "$2"; }

run_slice() {
  triple="$1"
  log="$WORK/$triple.log"

  xargs xcrun swiftc \
    -emit-module \
    -emit-module-path "$WORK/$triple.swiftmodule" \
    -sdk "$SDK_PATH" \
    -target "$triple" \
    -module-name Echo_Music \
    -parse-as-library \
    -swift-version 5 \
    <"$SOURCES" >"$log" 2>&1
  status=$?

  errors="$(grep -E ': error:' "$log" | sed -E 's|.*/Echo-Music/||;s|/Users/runner/[^ ]*/||' | sort -u)"
  count="$(printf '%s\n' "$errors" | grep -c 'error:' 2>/dev/null || true)"

  {
    echo "=== $triple -> exit=$status, errors=$count"
    if [ -n "$errors" ]; then
      printf '%s\n' "$errors" | head -20
    fi
    echo "--- tail of log"
    tail -12 "$log" | sed 's/^/    /'
  } >>"$REPORT"

  if [ -n "$errors" ]; then
    printf '%s\n' "$errors" | head -10 | while IFS= read -r line; do
      case "$line" in
        *": error:"*) ;;
        *) continue ;;
      esac
      path="${line%%:*}"
      rest="${line#*:}"
      lineno="${rest%%:*}"
      message="${line#*: error:}"
      message="${message#"${message%%[![:space:]]*}"}"
      case "$lineno" in
        *[!0-9]* | "") lineno=1 ;;
      esac
      printf '::error file=%s,line=%s,title=Swift error (%s)::%s\n' \
        "${path//%/%25}" "$lineno" "$triple" "${message//%/%25}"
    done
  else
    annotate "emit-module $triple" "clean (exit=$status)"
  fi
}

run_slice "arm64-apple-ios17.0-simulator"
run_slice "x86_64-apple-ios17.0-simulator"

# Which expressions cost the frontend the most time? A "the compiler is unable to
# type-check this expression in reasonable time" failure only shows up under load, so
# the ranking is what tells us whether that is what CI is hitting.
slow_log="$WORK/slowest.log"
xargs xcrun swiftc \
  -typecheck \
  -sdk "$SDK_PATH" \
  -target arm64-apple-ios17.0-simulator \
  -module-name Echo_Music \
  -parse-as-library \
  -swift-version 5 \
  -Xfrontend -debug-time-expression-type-checking \
  <"$SOURCES" >"$slow_log" 2>&1

slowest="$(awk '{ for (i = 1; i <= NF; i++) if ($i == "ms") { t = $(i - 1) + 0; if (t > 0) print t "\t" $0; break } }' \
  "$slow_log" | sort -rn | head -8 | sed -E 's|/Users/runner/[^ ]*/||' | cut -f2- | tr '\n' '|')"

{
  echo "=== slowest expressions (ms)"
  printf '%s\n' "$slowest"
} >>"$REPORT"
annotate "slowest expressions" "${slowest:-none measured}"

cat "$REPORT"

# Extra channel: PR comment (silently skipped when the token cannot write issues).
if [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "$GITHUB_EVENT_PATH" ]; then
  pr_url="$(jq -r '.pull_request.url // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)"
  if [ -n "$pr_url" ]; then
    payload="$(jq -Rs '{body: ("iOS build diagnostics\n\n```\n" + . + "\n```")}' "$REPORT" 2>/dev/null || true)"
    if [ -n "$payload" ]; then
      curl -s -o /dev/null --max-time 20 -X POST "$pr_url/comments" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "Content-Type: application/json" \
        -d "$payload" || true
    fi
  fi
fi

exit 0
