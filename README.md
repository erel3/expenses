# Expenses

What was spent, on the Mac (and later the iPhone): a widget with today's and this month's
spending by category and the latest payments, and a window listing every payment.

It reads the payments [expenses-capture](https://github.com/Erel3/expenses-capture) collects:
every bank push from the phone, appended by a Shortcuts automation to a JSON Lines file in
iCloud Drive. The file is only ever read here; the phone is its one writer.

- **Widget**, three sizes: today and this month; the month by category; the month with the latest
  payments. It keeps itself right across midnight and month ends without the app.
- **Window**: a month's payments by day with a category filter, and the raw pushes no parser
  understood yet (ads, transfers, declined attempts), so a new format is visible at a glance.
- **One parser**: the app runs expenses-capture's `parse.js` in JavaScriptCore, the same file the
  phone runs, so both always agree.
- Runs in the background to keep the widget current; the Dock icon shows only while the window is
  open. Tick *Open at login* in the window, or the widget stops updating after a restart.

## Build

Requires Xcode (Swift 6), [just](https://github.com/casey/just), and expenses-capture checked out
beside this repo (the expenses workspace does that).

```sh
just test      # unit and render tests (one compares the app's parsing with node's)
just app       # signed dist/Expenses.app with the widget and parse.js inside
just install   # replace /Applications/Expenses.app and register the widget
```

Signing uses a Developer ID; set `CODESIGN_ID` to your own identity.
