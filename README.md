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

All data is stored on-device (AsyncStorage) — no account needed for v1.

## Getting started

```bash
npm install
npx expo start
```

Then scan the QR code with [Expo Go](https://expo.dev/go) on your phone, or press `i` / `a` for a simulator, `w` for web.

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

- [ ] **Accounts & sync** — shared household backed by a realtime backend (Supabase), so each flatmate uses their own phone
- [ ] **Push notifications** — "Dima posted an ask", "Chris settled up"
- [ ] **Recurring chores** — rotating schedules (bins, bathroom, plants)
- [ ] **Shopping list** — shared list that turns purchases into expenses
- [ ] **Ask ↔ expense link** — "buy milk" ask completes into a logged expense
- [ ] **Household setup** — invite flow, custom names/colors, more than two flatmates (the balance math already supports n people)
