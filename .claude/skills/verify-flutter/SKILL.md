---
name: verify-flutter
description: Quick correctness gate for this Flutter app — runs static analysis then the test suite. Use after making code changes, before committing, or when asked to verify/check the project compiles and passes tests.
---

# verify-flutter

Run the project's fast verification gate and report results.

1. Run `flutter analyze` from the project root. Report any errors or warnings.
2. Run `flutter test`. Report pass/fail counts and any failing test names.

If `flutter analyze` reports errors, fix them (or surface them) before treating tests as meaningful. Test coverage in this repo is sparse, so a clean analyze pass is the primary signal.

Note: realtime (Socket.IO), WebRTC calls, and notification flows are NOT covered by these checks — they require a manual `flutter run --dart-define-from-file=.env.json` on a real device. Mention this when the change touches those areas.

This skill is additive to the bundled `/verify` skill, which drives the running app; use this one for a fast static + unit gate.
