# Roomies — working notes

Native iOS app. SwiftUI + Core Data mirrored to CloudKit. No server, no
third-party backend, no package dependencies.

## Layout

- `Roomies.xcodeproj` — uses Xcode 16 **synchronized folders**, so files added
  under `Roomies/` are picked up automatically. Do not hand-edit `project.pbxproj`
  to register new sources; just create the file.
- `Roomies/Model` — Core Data model, persistence, domain logic.
- `Roomies/Views` — SwiftUI screens and components.
- `Roomies/Support` — theme and formatting helpers.
- `Config/` — `Info.plist` and entitlements, deliberately outside the
  synchronized folder so they are not treated as bundle resources.

## Core Data + CloudKit constraints

CloudKit mirroring rejects models that break these rules, and the failure shows
up at store-load time rather than compile time:

- Every attribute must be **optional or carry a default value**.
- Every relationship must be **optional and have an inverse**.
- **No unique constraints** anywhere in the model.
- Entity classes are generated (`codeGenerationType="class"`). Never hand-write
  `Expense.swift` etc. — add conveniences in an extension instead.
- An attribute may not be called `description`; it collides with
  `NSObject.description`. The expense text is `title` for that reason.

## Two stores

`Persistence` loads two stores against the same model:

- `private.sqlite` → CloudKit private database: flats this device created.
- `shared.sqlite` → CloudKit shared database: flats a flatmate invited us into.

Fetches span both, so a `@FetchRequest` for `Household` returns either kind.
`Persistence.isOwner(of:)` distinguishes them by which store an object lives in.

## Sharing model

Flatmates are joined via **CKShare**, not an invite code. The owner taps
*invite*, which calls `NSPersistentCloudKitContainer.share(_:to:)` and presents
`UICloudSharingController`. The recipient taps the link; the app receives
`windowScene(_:userDidAcceptCloudKitShareWith:)` and calls
`acceptShareInvitations(from:into:)` against the shared store.

Names are stored as plain strings on records (as in the original), and this
device's own name lives in `UserDefaults` under `roomies.myName`. That keeps
"log an expense on behalf of a flatmate" working.

## Requirements worth remembering

- **CloudKit needs a paid Apple Developer Program membership.** Free
  provisioning cannot use the iCloud entitlement.
- Two different Apple IDs are needed to genuinely test sharing; the simulator
  can sign in to iCloud but sharing is far more reliable on device.
- Before a real release, push the schema to the CloudKit **production**
  environment in the CloudKit Console. Development schema is not used by
  App Store builds.
