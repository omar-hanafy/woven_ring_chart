#!/usr/bin/env bash
#
# The gate. Nothing is finished until this passes end to end.
#
#   bash tool/validate_all.sh
set -euo pipefail

package_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$package_dir"

flutter pub get
(cd example && flutter pub get)
python3 -B -m unittest discover -s tool -p 'test_*.py'
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --reporter expanded
(cd example && flutter analyze && flutter test --reporter expanded)
dart pub publish --dry-run
