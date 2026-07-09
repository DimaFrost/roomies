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

Then scan the QR code with [Expo Go](https://expo.dev/go) on your phone, or press `i` / `a` for a simulator, `w` for web.

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

## Roadmap

- [x] **Accounts & sync** — shared household backed by Supabase realtime, so each flatmate uses their own phone
- [ ] **Push notifications** — "Dima posted an ask", "Chris settled up"
- [ ] **Recurring chores** — rotating schedules (bins, bathroom, plants)
- [ ] **Shopping list** — shared list that turns purchases into expenses
- [ ] **Ask ↔ expense link** — "buy milk" ask completes into a logged expense
- [ ] **Household setup** — invite flow, custom names/colors, more than two flatmates (the balance math already supports n people)
