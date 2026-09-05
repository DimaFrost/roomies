# at our place 🏠

**A flatmates OS.** One app for everything you share with the people you live with — money, favours, and when everyone's around.

Native Swift/SwiftUI, iOS only. Sync is [CloudKit](https://developer.apple.com/icloud/cloudkit/) — no third-party backend, no signup, no passwords: flatmates share a household through their existing iCloud accounts via `CKShare`.

> **History:** this started as an Expo/React Native app synced through Supabase, targeting iOS, Android, and web. It's now a Swift-native, CloudKit-only build — trading Android/web for a backend-free architecture. The old Expo source is still in the repo root (`App.tsx`, `src/`, `supabase/`) but is no longer the app; everything current lives in `native/`.
>
> The repo, bundle identifier (`com.madebyfrost.roomies`), and internal type names still say "roomies" — only the user-facing name changed. Renaming those would orphan the App Store Connect record and CloudKit container.

## Features

### 💶 Split — expense tracking
- Log shared expenses with categories, back-dating to any past day
- Split evenly across the household, or assign the full amount to one person
- Live "who owes what" panel that nets everything into the minimal set of transfers
- One-tap **Settle** records the payback and zeroes the balance
- Only the person who paid can delete an expense

### 🤝 Asks — post a favour
- Post an ask — "water my plants", "grab milk on your way home" — for a specific flatmate or anyone
- Quick templates for the usual favours
- Flatmates accept ("I'm on it"), then mark done
- Open-ask badge on the tab so nothing gets missed

### 🗓 Plans — shared availability, private details
- Connect your phone calendar and Roomies publishes **only busy blocks** — start and end times, no event names
- All-day events get an explicit per-event opt-in to share the name, since "Travelling to London" is useful context
- No calendar access? Log travel and plans by hand instead, with a per-plan "share the name" toggle
- Invite flatmates along to a plan you're creating

### 🏠 Flat — household management
- Rename the flat, invite flatmates (opens the iCloud share sheet), remove flatmates
- Ground truth everyone should agree on: monthly rent amount and due day
- Recurring bills (internet, electricity…) with due days

### ☁️ Sync
- First launch: create a flat, then invite a flatmate by the email or phone their Apple Account uses
- Everything syncs between devices through a shared CloudKit record zone
- Access control is iCloud's: only share participants can read or write the zone
- Writes that can't reach iCloud are queued on disk and replayed, and the last synced state is cached so the app opens and works offline

## Getting started

Requires Xcode and a paid Apple Developer account (CloudKit and device installs need real signing).

```bash
brew install xcodegen          # the .xcodeproj is generated, not committed
cd native
xcodegen generate
open Roomies.xcodeproj
```

Then pick a device and hit Run. From the CLI:

```bash
# simulator (note: CloudKit needs an iCloud account signed into the simulator)
xcodebuild -project Roomies.xcodeproj -scheme Roomies \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# a real device — recommended, CloudKit sharing and push behave properly here
xcrun devicectl list devices
xcodebuild -project Roomies.xcodeproj -scheme Roomies \
  -destination 'platform=iOS,id=<DEVICE_UDID>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <DEVICE_UDID> <path-to>/Roomies.app
```

**Do not edit the project in Xcode's file/build-settings UI** — `project.yml` is the source of truth and `xcodegen generate` overwrites the `.xcodeproj`.

### ⚠️ Invites are bound to an Apple Account, not to the link

`share.publicPermission` is `.none` on flats created from now on. The invite URL is an address,
not a key: access comes from being an explicit participant, added via
`CKContainer.shareParticipant(forEmailAddress:)` / `forPhoneNumber:` in
`HouseholdStore.inviteFlatmate`. Forwarding the link gets the next person nothing, and
`removeMember` genuinely revokes.

Flats created **before** this change still have `publicPermission = .readWrite`, where the link
alone grants full access forever. Those are not migrated automatically, and deliberately so:
anyone who joined through an open link is a `.publicUser` whose access derives from that setting,
CloudKit offers no way to promote them in place, and someone who was sent the link but hasn't
accepted yet doesn't appear in `share.participants` at all. Closing the link around either group
locks them out. The owner gets the names of anyone affected plus an explicit "Close the old link"
action in `InviteLinkView`; nothing closes on its own.

### ⚠️ CloudKit schema gotcha (read this before shipping)

CloudKit has two environments, and they behave differently:

- **Development** — record types and fields are created automatically the first time the app saves a record of that type.
- **Production** — never auto-creates anything. A build talking to Production against an undeployed schema fails with **"did not find record type: X"**.

So after adding or changing any record type, you must: exercise the new write once on a Development build, then open the [CloudKit Console](https://icloud.developer.apple.com/) → **Deploy Schema Changes** to push it to Production. TestFlight and App Store builds use Production.

Current record types: `Household`, `Member`, `Expense`, `Ask`, `Bill`, `PlanEvent`.

Related trap: `CKQuery` requires a *queryable* index — even a match-everything predicate needs `recordName` marked queryable. This app deliberately avoids queries entirely and reads whole zones with `CKFetchRecordZoneChangesOperation`, which has no index dependency.

## TestFlight

The archive path is already configured (signing team, icon, version, encryption declaration):

```bash
cd native
xcodebuild archive -project Roomies.xcodeproj -scheme Roomies \
  -archivePath /tmp/Roomies.xcarchive -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates
open /tmp/Roomies.xcarchive
```

Then in Organizer: **Distribute App → App Store Connect → Upload**. Once processed, add internal testers in App Store Connect → TestFlight (instant, no review).

## Project layout

```
native/
  project.yml                    XcodeGen spec — the source of truth for the Xcode project
  Roomies/Sources/
    App/                         app entry point, AppDelegate (CKShare acceptance, push)
    Models/                      Expense/Ask/Bill/PlanEvent, balance math, time formatting
    Store/
      HouseholdStore.swift       CloudKit zone + share, all reads/writes, app phase
      CalendarService.swift      EventKit reader (local only — never uploads directly)
    Theme/                       colors, member palette, fonts
    Components/                  Avatar, Card, Tag, PersonPicker, FlowLayout, share sheet
    Screens/                     ContentView shell + Expenses, Asks, Plans, Settings, onboarding
```

## Known gaps

- **Fonts** are system fonts; the original DM Sans / DM Mono / Syne files aren't bundled yet
- **Calendar sync is manual** (a "Sync availability" button), not background
- **Names must be unique** within a household — the balance math keys off name strings, and duplicate members are merged on refresh
- Sync is a full zone re-fetch on launch/foreground/push rather than `CKSyncEngine` incremental sync — fine at household data volumes
- **Pre-existing flats still have an open invite link** until their owner closes it — see the invites section above

## Roadmap

- [x] **Accounts & sync** — CloudKit shared zone, no signup
- [x] **Household management** — invite/remove flatmates, rent + recurring bills
- [x] **Plans** — privacy-preserving shared availability
- [ ] **Push notifications** — "Dima posted an ask", "Chris settled up" (subscriptions are registered; no user-facing alerts yet)
- [ ] **Recurring chores** — rotating schedules (bins, bathroom, plants)
- [ ] **Shopping list** — shared list that turns purchases into expenses
- [ ] **Ask ↔ expense link** — "buy milk" ask completes into a logged expense
- [ ] **Bills → expenses** — recurring bills auto-log on their due day
```
