# Roomies 🏠

**A flatmates OS.** One app for everything you share with the people you live with — starting with money, growing into favours, chores, and everything else that keeps a flat running.

Built with [Expo](https://expo.dev) / React Native, so it runs as a real mobile app on iOS and Android (and on the web).

## Features

### 💶 Split — expense tracking
- Log shared expenses with categories (food, groceries, rent, …)
- Split evenly across the household, or assign the full amount to one person
- Live "who owes what" panel that nets everything into the minimal set of transfers
- One-tap **Settle** records the payback and zeroes the balance
- Full history with long-press to delete

### 🤝 Asks — post a favour
- Post an ask — "water my plants", "grab milk on your way home" — for a specific flatmate or anyone
- Quick templates for the usual favours
- Flatmates accept ("I'm on it"), then mark done
- Open-ask badge on the tab so nothing gets missed

### ☁️ Sync — every flatmate on their own phone
- First launch: create a flat (you get a 6-letter invite code) or join with a code
- Everything syncs live between phones via Supabase realtime
- No signup friction: each device gets an invisible auto-provisioned account
- Access is enforced server-side with Postgres row-level security — only members of your flat can read or write its data
- Without a configured backend (`.env` absent) the app falls back to single-device local mode

## Getting started

```bash
npm install
npx expo start
```

Then scan the QR code with [Expo Go](https://expo.dev/go) on your phone, or press `i` / `a` for a simulator, `w` for web. If your phone isn't on the same Wi-Fi as your computer, use `npx expo start --tunnel`.

### ⚠️ SDK version gotcha (read before bumping `expo`)

Expo Go on the App Store / Play Store only runs projects built on the **SDK it
was compiled for** — and the store apps trail npm by weeks. The store's Expo Go
is currently on **SDK 54**, so this project is pinned to `expo@~54.0.0`. That is
deliberate.

`create-expo-app` and `npx expo install expo@latest` will happily pull a *newer*
SDK (npm's `latest` was already SDK 57), which then fails to open in Expo Go with
**"Project requires a newer version of Expo Go."** The project isn't broken — it's
ahead of the released client.

Rules of thumb:
- Staying on Expo Go for testing → keep the `expo` major at whatever the store's
  Expo Go supports. To realign every dependency after changing it:
  `npm install expo@~54.0.0 && npx expo install --fix`.
- Need a newer SDK (or want to stop caring about this) → move to a **development
  build** (`expo-dev-client` + EAS), which bundles its own native runtime and is
  not tied to store Expo Go. See **Distribution & remote testing** below.

## Backend

The Supabase backend lives in the `deurbanize` project (shared, everything
prefixed `roomies_`). Client config is in `.env` (publishable values only).
The schema, RLS policies, and RPCs are in `supabase/migrations/` and the
device-account edge function in `supabase/functions/roomies-create-device-user/`
— both already applied/deployed. To move to a dedicated project later: create
it, run the migrations, deploy the function (`verify_jwt` off), and update `.env`.

## Project layout

```
App.tsx                    app shell: fonts, header, bottom tabs
src/
  theme.ts                 colors, fonts, member palette
  types.ts                 Expense / Ask / household types
  store.tsx                household state + AsyncStorage persistence
  lib/
    balances.ts            balance + minimal-settlement math (pure)
    confirm.ts             cross-platform confirm dialog
    time.ts                relative timestamps, ids
  components/              Avatar, Card, Tag, PersonPicker
  screens/
    ExpensesScreen.tsx     add expense, history, settlements panel
    AsksScreen.tsx         post / accept / complete asks
```

## Distribution & remote testing

Expo Go + LAN (or `--tunnel`) is fine for solo iteration, but for testers who
aren't next to your laptop, use [EAS](https://docs.expo.dev/eas/) (Expo's cloud
build/submit/OTA service). The ladder, least → most effort:

| Goal | Tool | Notes |
| --- | --- | --- |
| Test off your Wi-Fi, still Expo Go | `npx expo start --tunnel` | Zero setup; laptop must stay running; still bound to store Expo Go's SDK |
| Push JS updates over-the-air | `eas update` | Testers pull new JS into an existing build; no rebuild for JS-only changes |
| Your own installable app (no SDK ceiling) | `eas build` + `expo-dev-client` | Custom native runtime; unlocks any SDK; install once, then OTA |
| Remote testers, no cables | **TestFlight** via `eas build` + `eas submit` | The real answer for on-device remote testing (paid Apple Developer account) |

**Recommended for this project** (you have a paid Apple Developer account + Xcode):

1. `npm i -g eas-cli && eas login`
2. `eas build:configure` — generates `eas.json`
3. `eas build --platform ios --profile preview` — EAS builds & signs in the
   cloud (it can manage your Apple certs/profiles for you)
4. `eas submit --platform ios --latest` — uploads to App Store Connect →
   **TestFlight**
5. Add testers in App Store Connect:
   - **Internal** (up to 100, on your team): builds appear instantly, no review
   - **External** (up to 10,000, via public link): one-time lightweight beta review

For the tightest dev loop, add `expo-dev-client` and pair a **development build**
with `eas update` — install the dev build once per device, then ship JS changes
OTA without rebuilding. Moving to any EAS build also lets you leave SDK 54 behind
(see the SDK gotcha above), since the app then carries its own runtime.

## Roadmap

- [x] **Accounts & sync** — shared household backed by Supabase realtime, so each flatmate uses their own phone
- [ ] **Push notifications** — "Dima posted an ask", "Chris settled up"
- [ ] **Recurring chores** — rotating schedules (bins, bathroom, plants)
- [ ] **Shopping list** — shared list that turns purchases into expenses
- [ ] **Ask ↔ expense link** — "buy milk" ask completes into a logged expense
- [ ] **Household setup** — invite flow, custom names/colors, more than two flatmates (the balance math already supports n people)
