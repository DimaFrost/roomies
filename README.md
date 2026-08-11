# Roomies 🏠

**A flatmates OS.** One app for everything you share with the people you live with — starting with money, growing into favours, chores, and everything else that keeps a flat running.

A native iPhone app: SwiftUI, Core Data, and CloudKit. No server, no accounts, no third-party dependencies — the flat lives in your own iCloud.

## Features

### 💶 Split — expense tracking
- Log shared expenses with categories (food, groceries, rent, …)
- Split evenly across the flat, or assign the full amount to one person
- Live "who owes what" panel that nets everything into the minimal set of transfers
- One-tap **Settle** records the payback and zeroes the balance
- Full history; long-press an entry to delete it

### 🤝 Asks — post a favour
- Post an ask — "water my plants", "grab milk on your way home" — for a specific flatmate or anyone
- Quick templates for the usual favours
- Flatmates accept ("I'm on it"), then mark done
- Open-ask badge on the tab so nothing gets missed

### ☁️ Sync — every flatmate on their own iPhone
- Create a flat, then tap **invite** and send the link however you like — Messages, WhatsApp, AirDrop
- Your flatmate opens the link and the flat appears on their phone, expenses and asks included
- Changes sync both ways over CloudKit, usually within seconds
- No sign-up, no passwords, no backend of ours: identity is the iCloud account already on the phone
- Everything also works offline and syncs when the phone reconnects

## Requirements

- Xcode 16 or newer, iOS 17+ target
- **A paid Apple Developer Program membership.** CloudKit is not available with
  free provisioning, so the app cannot sync (or even launch its store) without it.
- An iCloud account signed in on each device

## Getting started

1. Open `Roomies.xcodeproj` in Xcode.
2. Select the **Roomies** target → *Signing & Capabilities*, and set your team.
   Signing is automatic; the CloudKit container is declared in
   `Config/Roomies.entitlements` as `iCloud.com.dimafrost.roomies`.
3. If you use a different bundle identifier, change `PRODUCT_BUNDLE_IDENTIFIER`
   and update the container ID in both the entitlements file and
   `Persistence.cloudKitContainerIdentifier` so all three agree.
4. Build and run on a device (⌘R).

The first launch creates the CloudKit schema in the *development* environment
automatically. Before shipping, promote it to production in the
[CloudKit Console](https://icloud.developer.apple.com/).

### Testing sync properly

Sharing is between **two different Apple IDs**, so a single simulator can't show
you the real thing. Run on your own iPhone, tap *invite*, and send the link to a
second device signed in as someone else.

## How sync works

Core Data mirrors to CloudKit through `NSPersistentCloudKitContainer`, with two
stores loaded against one model:

| Store | CloudKit database | Holds |
| --- | --- | --- |
| `private.sqlite` | private | flats this device created |
| `shared.sqlite` | shared | flats a flatmate invited us into |

Fetches span both stores, so the UI does not care which kind of flat it is
showing. Inviting a flatmate creates a `CKShare` over the `Household` record;
because every expense, ask, and member hangs off that household, the whole flat
travels with the share.

## Project layout

```
Roomies.xcodeproj          Xcode 16 synchronized-folder project
Config/
  Info.plist               dark-only, portrait, remote-notification background mode
  Roomies.entitlements     CloudKit container + push
Roomies/
  RoomiesApp.swift         app entry, scene delegate that accepts share invites
  Model/
    Roomies.xcdatamodeld   Household / Member / Expense / Ask
    Persistence.swift      two-store CloudKit stack, CKShare helpers
    HouseholdStore.swift   mutations, plus this device's member name
    Domain.swift           typed accessors, categories, quick asks
    Balances.swift         balance + minimal-settlement math (pure)
  Views/
    RootView.swift         header, bottom tabs, invite affordance
    SplitView.swift        add expense, history, settlements panel
    AsksView.swift         post / accept / complete asks
    WelcomeView.swift      create a flat; claim a name after accepting an invite
    CloudSharingSheet.swift  UICloudSharingController bridge
    Components.swift       Avatar, Card, Tag, PersonPicker, chips, flow layout
  Support/
    Theme.swift            colours, member palette, font roles
    RelativeTime.swift     relative timestamps, euro formatting
```

## Notes on the port

This started as an Expo/React Native app backed by Supabase. Re-scoping it to
iOS-only let the backend disappear entirely — CloudKit replaces Postgres, row
level security, device accounts, and the invite-code table with the iCloud
account already on the phone.

Two visible consequences:

- **Invite codes are gone.** Joining is a share link, which is both less to
  build and less to mistype.
- **Fonts are the system faces.** The original used DM Sans / DM Mono / Syne from
  Google Fonts; the SwiftUI build maps those roles onto San Francisco
  (`.rounded` for display, `.monospaced` for figures) so nothing is bundled and
  Dynamic Type keeps working.

The balance and settlement math was checked against the original implementation
over 4,000 generated scenarios: balances are identical in every case. Settlements
differ only when two people owe exactly the same amount — Swift randomises
dictionary order, so ties are now broken by name to stop the list reshuffling on
each redraw. The number of transfers and the amounts are unchanged.

## Roadmap

- [x] **Accounts & sync** — shared flat over CloudKit, each flatmate on their own phone
- [ ] **Push notifications** — "Dima posted an ask", "Chris settled up"
- [ ] **Recurring chores** — rotating schedules (bins, bathroom, plants)
- [ ] **Shopping list** — shared list that turns purchases into expenses
- [ ] **Ask ↔ expense link** — "buy milk" ask completes into a logged expense
- [ ] **Widgets & Live Activities** — balance on the home screen
- [ ] **Apple Watch companion** — tick off an ask from your wrist
