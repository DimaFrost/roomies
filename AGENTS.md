# This is a native Swift app now, not Expo

The app lives entirely in `native/`. It's SwiftUI + CloudKit, built via an Xcode project
generated from `native/project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) —
run `xcodegen generate` after any `project.yml` change, and never hand-edit
`native/Roomies.xcodeproj` in Xcode's file/build-settings UI, since it gets overwritten.

See `README.md` for the full build/run/TestFlight instructions and the CloudKit
Development-vs-Production schema gotcha — read that section before adding a new record type.
