# 9 — Screenshots

The reference app's main screens, as a port should look and behave. The images are generated,
not hand-made: `BugCoffeeUITests/ScreenshotTests.swift` walks the app and writes them to
[`screenshots/<device>/`](screenshots/). Regenerate them after any UI change (§ Regenerating).

The app on two devices: **iPhone 17 Pro** (portrait only, like the app) and **iPad mini (A17 Pro)** in
**portrait and landscape**. Plus the **Stamp Card widget** on an iPhone home screen and the **Watch
app** on an Apple Watch Series 11 (46mm). On iPad each screen is captured, then the device is rotated with
the screen still up — so the landscape shots also check that a sheet or the open bean page
survives rotation (doc 8, test 45).

All data shown is made up: a demo account (`ana@example.com`), 6 stamps, Flat White and Kultura
starred, and a short tasting diary.

---

## iPhone

### Sign-in and card (doc 1 §2–4)

| Login | Card |
|-------|------|
| <img src="screenshots/iphone-17-pro/01-login.png" width="260" alt="Login screen"> | <img src="screenshots/iphone-17-pro/02-card.png" width="260" alt="Loyalty card with QR and 6 of 9 stamps"> |

### Products (doc 1 §5–6)

| Menu | Bean page | Add a cup | Find my blend |
|------|-----------|-----------|---------------|
| <img src="screenshots/iphone-17-pro/03-products.png" width="200" alt="Products list, favorites on top"> | <img src="screenshots/iphone-17-pro/04-bean-page.png" width="200" alt="Kultura House Blend with a 3-cup diary"> | <img src="screenshots/iphone-17-pro/05-tasting-editor.png" width="200" alt="Tasting editor sheet"> | <img src="screenshots/iphone-17-pro/06-blend-finder.png" width="200" alt="Blend quiz, Chocolate & nuts"> |

---

## iPad mini

The regular-width layouts: the card splits into a QR half and a stamps/actions half (side by
side in landscape, stacked in portrait), and Products is a split view with the bean page next
to the list.

| Screen | Portrait | Landscape |
|--------|----------|-----------|
| Login | <img src="screenshots/ipad-mini-a17-pro/01-login-portrait.png" width="240" alt="Login, iPad portrait"> | <img src="screenshots/ipad-mini-a17-pro/01-login-landscape.png" width="340" alt="Login, iPad landscape"> |
| Card | <img src="screenshots/ipad-mini-a17-pro/02-card-portrait.png" width="240" alt="Card, iPad portrait"> | <img src="screenshots/ipad-mini-a17-pro/02-card-landscape.png" width="340" alt="Card, iPad landscape"> |
| Products | <img src="screenshots/ipad-mini-a17-pro/03-products-portrait.png" width="240" alt="Products, iPad portrait"> | <img src="screenshots/ipad-mini-a17-pro/03-products-landscape.png" width="340" alt="Products, iPad landscape"> |
| Bean page | <img src="screenshots/ipad-mini-a17-pro/04-bean-page-portrait.png" width="240" alt="Bean page, iPad portrait"> | <img src="screenshots/ipad-mini-a17-pro/04-bean-page-landscape.png" width="340" alt="Bean page, iPad landscape"> |
| Add a cup | <img src="screenshots/ipad-mini-a17-pro/05-tasting-editor-portrait.png" width="240" alt="Add a cup, iPad portrait"> | <img src="screenshots/ipad-mini-a17-pro/05-tasting-editor-landscape.png" width="340" alt="Add a cup, iPad landscape"> |
| Find my blend | <img src="screenshots/ipad-mini-a17-pro/06-blend-finder-portrait.png" width="240" alt="Find my blend, iPad portrait"> | <img src="screenshots/ipad-mini-a17-pro/06-blend-finder-landscape.png" width="340" alt="Find my blend, iPad landscape"> |

---

## Widgets

The Stamp Card home-screen widget (doc 1), added through the real widget gallery and showing the
demo account's 6 stamps. The gallery preview always shows 4 — that's the widget's `isPreview`
snapshot, not the stored count.

| Gallery | Home screen | Small | Medium |
|---------|-------------|-------|--------|
| <img src="screenshots/iphone-17-pro/07-widget-gallery.png" width="200" alt="Widget gallery, Stamp Card small size"> | <img src="screenshots/iphone-17-pro/08-widgets-home.png" width="200" alt="Home screen with the medium and small Stamp Card widgets"> | <img src="screenshots/iphone-17-pro/09-widget-small.png" width="150" alt="Small widget, 6 of 9 stamps"> | <img src="screenshots/iphone-17-pro/10-widget-medium.png" width="280" alt="Medium widget, 6 of 9 stamps, 3 to a free drink"> |

---

## Apple Watch

The Watch app with the same demo account synced: the QR the phone sends over, 6 stamps, caffeine
logging and the beans wizard (here With milk + Chocolate & nuts). The last shot is what a watch
shows before the phone has synced an account.

| Home | Card | Stamps | Log caffeine |
|------|------|--------|--------------|
| <img src="screenshots/apple-watch-series-11-46mm/01-home.png" width="170" alt="Watch home menu"> | <img src="screenshots/apple-watch-series-11-46mm/02-card.png" width="170" alt="Loyalty QR on the watch"> | <img src="screenshots/apple-watch-series-11-46mm/03-stamps.png" width="170" alt="Stamp card, 6 of 9"> | <img src="screenshots/apple-watch-series-11-46mm/04-log-caffeine.png" width="170" alt="Log caffeine list"> |

| Find my blend | Matches | Not signed in |
|---------------|---------|---------------|
| <img src="screenshots/apple-watch-series-11-46mm/05-find-my-blend.png" width="170" alt="Blend wizard questions"> | <img src="screenshots/apple-watch-series-11-46mm/06-blend-matches.png" width="170" alt="Blend matches"> | <img src="screenshots/apple-watch-series-11-46mm/07-signed-out.png" width="170" alt="Sign in on your iPhone prompt"> |

---

## Regenerating

```bash
Scripts/take_screenshots.sh
```

The script runs three passes, one after the other:

| Pass | Tests | Simulator | Output |
|------|-------|-----------|--------|
| `app` | `BugCoffeeUITests/ScreenshotTests` (`BugCoffee` scheme) | **iPhone 17 Pro** + **iPad mini (A17 Pro)**, in parallel | `iphone-17-pro/01…06`, `ipad-mini-a17-pro/` |
| `watch` | `BugCoffeeWatchUITests` (`BugCoffeeWatch` scheme) | **Apple Watch Series 11 (46mm)** | `apple-watch-series-11-46mm/` |
| `widgets` | `BugCoffeeUITests/WidgetScreenshotTests` | a **temporary** iPhone 17 Pro, deleted afterwards | `iphone-17-pro/07…10` |

Simulators are picked on the runtimes that match the active Xcode's iOS and watchOS SDKs. iOS status
bars are pinned to 9:41 on a fixed date with full battery; watchOS has no status bar override, so
the watch shots show the time they were taken. Each device writes to a folder named after the
simulator (`iPad mini (A17 Pro)` → `ipad-mini-a17-pro/`); iPads get `-portrait` and `-landscape`
variants of every screen. Options (environment variables):

| Variable | Default | |
|----------|---------|---|
| `SHOTS` | `app,watch,widgets` | which passes to run, e.g. `SHOTS=watch` |
| `DEVICES` | `iPhone 17 Pro,iPad mini (A17 Pro)` | comma-separated simulator names for `app` |
| `WATCH_DEVICE` | `Apple Watch Series 11 (46mm)` | |
| `WIDGET_DEVICE` | `iPhone 17 Pro` | device type of the temporary simulator |
| `OUT_DIR` | `docs/screenshots` | root folder; device folders go inside |
| `DEVELOPER_DIR` | `xcode-select`'s Xcode | e.g. `/Applications/Xcode-RC.app/Contents/Developer` for iOS 27 |

Each PNG is also attached to the test result (Xcode's Report navigator), so a run from Xcode
works too: ⌘U on the `BugCoffee` scheme for the app screens (the widget test skips itself there),
⌘U on `BugCoffeeWatch` for the watch. Either writes to the folder of whichever simulator you picked.

How the tests stay deterministic and harmless:

- **No sign-in, no network.** The account, stamp count, favorites and diary are passed as launch
  arguments (`-bug-coffee.uid …`). They land in the *argument domain*, which overrides standard
  and App Group defaults for that launch only — a real login or diary on the simulator is not
  read and not overwritten.
- **No refresh token**, so the App Check WebView (doc 2 §5) never starts; the card shows
  "Backend: no token — manual count only".
- The **Watch** tests pass the account, stamp count and the loyalty QR PNG (generated on a Mac —
  CoreImage isn't on watchOS) the same way, so the watch needs no paired phone.
- The **widget** test is the exception: a widget can't see the app's launch arguments, so it
  signs in the demo account, taps + on the card until it reads 6 (which writes the App Group) and
  then drives SpringBoard to add the widgets. That changes the simulator, which is why it only
  runs with `SCREENSHOTS_WIDGETS=1` on the throwaway simulator the script creates.
- The **Add a cup** date defaults to today, so `05-tasting-editor.png` changes day to day.
- The watch simulator sometimes fails to relaunch the app between tests; the script retries a
  failed watch test up to 3 times.

To add a screen: add a `testNN…` method that navigates there and calls `snapshot("NN-name")`,
then add the image to the tables above (both devices). For the watch, the same in
`BugCoffeeWatchUITests/WatchScreenshotTests.swift` with `capture("NN-name")`.
