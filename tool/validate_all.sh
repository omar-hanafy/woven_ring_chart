#!/usr/bin/env bash
#
# The gate. Nothing is finished until this passes end to end.
#
#   bash tool/validate_all.sh
set -euo pipefail

package_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$package_dir"

dart format --output=none --set-exit-if-changed lib test tool example/lib example/test
dart analyze
flutter test --reporter expanded
(cd example && flutter test --reporter expanded)
dart pub publish --dry-run
