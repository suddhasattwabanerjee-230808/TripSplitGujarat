# Changelog

All notable changes to this project are documented here. Versions follow
[Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`); the build
number after `+` in `pubspec.yaml` increments on every release.

## [1.14.3] - 2026-10-22 (build 40)

### Added
- Balance (in the trip's Quick Actions) has a "You And Each Person"
  section: your balance with each tripmate, worked out. Tap a person to see
  what you paid for them, what they paid for you, every settle-up between
  you (part payments included, with dates) and the balance now.

### Changed
- A settle-up now ends with one short line: "₹500 Settled With Aarav".

## [1.14.2] - 2026-10-22 (build 39)

### Fixed
- Paying a tripmate in Google Pay or PhonePe opens the payment with their
  UPI ID and the amount you entered already filled in: TripSplit hands the
  app a payment QR, which it reads like a scanned code. If an app doesn't
  take it, the UPI ID is copied to paste as before.

### Changed
- TripSplit stops watching for the bank's SMS two minutes after you start
  a settle-up payment, then offers "Mark Paid".
- The intro's ajrakh print is darker and more sheer.

## [1.14.1] - 2026-10-22 (build 38)

### Fixed
- Paying a tripmate in a UPI app: their UPI ID is now copied and the app
  opens for you to paste it (Google Pay straight on "Pay phone number /
  UPI ID"), instead of a filled-in payment link, which UPI apps often
  decline for personal UPI IDs. Your bank's SMS still confirms the payment
  and updates the balances.

### Changed
- Add Expense fits on one screen: what and amount side by side, when and
  location side by side, and six categories as tiles (Food, Stay,
  Transport, Fuel, Shopping, Activities) plus Other. Groceries, Rent,
  Utilities and custom categories are gone from the form; older expenses
  keep theirs.
- More room between the bottom bar's buttons.

## [1.14.0] - 2026-10-22 (build 37)

### Added
- Part settlements: Settle Up has an amount field, filled with the full
  amount. Pay less and the rest stays owed; UPI apps, Scan QR, cash and the
  bank-SMS check all use the amount you entered.
- The ＋ button opens an Add Expense page. Saving shows "Expense Added",
  then goes back to the trip.
- App Settings, a page of its own from the profile: notifications, app
  font, bold text, a text size slider, and updates.

### Changed
- The bottom bar works like ShotDrop's: the open tab becomes a filled pill
  with its name, the others are icons, and ＋ stays the same. It hides
  while the keyboard is open.
- The Trip page no longer has its own Add Expense button.

### Fixed
- Smoother scrolling: the bottom bar no longer blurs what's behind it,
  the trip page's sections and the city photo aren't repainted on every
  frame, and a tripmate's change no longer redraws every page.

## [1.13.0] - 2026-10-22 (build 36)

### Added
- Settle-ups paid in a UPI app confirm themselves: TripSplit watches for
  your bank's UPI debit SMS for that amount (for up to 30 minutes) and
  records the payment, instead of asking whether it went through. Without
  SMS access, or if no SMS comes, a "Mark Paid" button shows instead.
- App Font in the profile: 46 fonts (sans serif, serif and rounded), applied
  across the whole app. Each downloads the first time you pick it.
- Bold Text, in the profile and on the App Font page.
- A UPI Alerts button in Quick Actions, to switch UPI payment alerts on or
  off.
- Invite People on the Trip Details page.

### Changed
- The bottom bar is just Trip, Add and Expenses. It shrinks to its icons as
  you scroll and opens out again at the top of the page.
- Quick Actions: Balance, UPI Alerts, Scan Receipt and View Stats.
- The date next to the trip type is today's date.
- The intro plays only when the app was closed for a minute or more.

## [1.12.0] - 2026-10-22 (build 35)

### Added
- Settle up: "Scan Their QR Code" lists your UPI apps (Google Pay and
  PhonePe first) and opens the one you pick straight on its scanner, then
  asks whether the payment went through.
- A photo of the city you're in behind the profile header and the trip
  card, blended into the app's colours. It asks for location once.
- "All Notifications" in the profile's App section: one switch for expense
  alerts, settle-up reminders and UPI payment alerts.
- "Check For Updates At Launch", with a switch in the profile's App
  section. A new version shows as a bar with an Update button, and the
  update sheet shows what's new and the download's progress.
- Tapping a notification on the bell's page opens that expense.

### Changed
- The bottom bar floats, and the Profile tab is gone: your photo at the top
  of the Trip page opens your profile. Invite moved into Quick Operations.
- The profile's Account section is gone. Your UPI ID is now a chip under
  your name; tap the photo or the name to change them.
- A new font, Inter, everywhere.
- Labels, buttons and titles now capitalise every word.
- On the Expenses tab: "Trip Mates", "All Mine", "Paid By Me" and "Others
  Paid For Me".
- The intro uses the new lion logo on an ajrakh print, and only plays when
  the app was closed for 30 seconds or more.

### Fixed
- Settle up found no UPI apps on some phones (Google Pay and PhonePe hide
  their payment links from other apps until they're set up).

## [1.11.0] - 2026-10-22 (build 34)

### Added
- An Expenses tab in the bottom bar, with everything about the trip's
  expenses:
  - Three views: the whole trip, per person (pick anyone to see what they
    paid, their share and where they stand), and Me (all mine, what I paid,
    or what others paid for me).
  - Search by description, place, category, who paid or amount.
  - Filters: a date range, a time window (e.g. 6–10 PM, even past
    midnight), morning / afternoon / evening / night, categories,
    locations, who paid, an amount range, and settle-ups on or off. They
    combine, and the button shows how many expenses are left.
  - Sort by newest, oldest, highest or lowest amount.
  - A summary at the top (paid, share, net) with a category split bar.
  - Tap an expense for its details; edit or delete your own, as before.
- Richer trip insights as swipeable cards, with chips to jump between them:
  an overview (per day, per person, average bill, biggest expense, top
  category, spending pace), by date with the daily average marked, by
  category with counts and percentages, by person, who's ahead (who gets
  money back and who owes), by location, by time of day, and the biggest
  expenses.

### Changed
- New colours from the logo: its orange with deep wine reds, in place of
  the blue and purple. The dark theme is now a warm, deep black with the
  logo's orange.
- Everyone's photos now sit beside the trip total on the trip card.
- The trip page no longer lists expenses (they're on the Expenses tab); a
  card there opens them.
- The bottom bar is Trip · Expenses · ＋ · Balance · Stats · Profile.

## [1.10.1] - 2026-10-22 (build 33)

### Added
- Instant expense notifications: when someone adds an expense, everyone else
  on the trip gets it on their phone straight away, even with TripSplit
  closed and the phone locked (before, it could take up to 15 minutes).
  Open this version once and allow notifications so your phone can receive
  them. If they don't arrive on your phone, set TripSplit's Battery setting
  to Unrestricted.

## [1.10.0] - 2026-10-21 (build 32)

### Added
- Your trip's page is now its dashboard (still the first thing you see): the
  trip total up top with your share, what you paid and where you stand, then
  insights for that trip: by date (each day, the busiest day, the daily
  average), by category, by person (who paid, or each person's share) and by
  location (each city). Switch between the whole trip and just your share.
  The expense list follows, as before.

### Changed
- A richer, more polished look: the Manrope typeface throughout, deeper
  colours, and cards with soft depth instead of flat outlines.
- The bottom bar is Trip · Balance · ＋ · Statistics · Profile, with a raised
  button in the middle to add an expense.

## [1.9.0] - 2026-10-21 (build 31)

### Added
- Dark theme: a deep, classy dark look for the whole app. Flip it any time
  with the sun / moon at the top of every screen; it remembers your choice.
- Paying a tripmate: pick your UPI app (Google Pay, PhonePe, Paytm…). With
  their UPI ID it opens on the payment, filled in; without one it opens so
  you can scan their QR. "I paid in cash" is still there.
- Remind me to settle later: choose a date and time; the reminder opens that
  exact balance with the same ways to pay. For money owed to you, the alarm
  button on the row sets a follow-up reminder.
- Change your profile photo (tap it in Profile), or go back to your Google one.
- Give tripmates your own nicknames from their page: only you see them, and
  they're used everywhere in the app.
- Tap anyone's photo or name to open their page.
- The Google logo next to your email in Profile.
- Phone notifications when someone on your trips adds an expense: their
  photo, name and the amount, plus what it was for, the category, trip,
  place, time and your share. Tap one to see the expense. They show straight
  away while TripSplit is open or in the background, and within about 15
  minutes when it's closed.
- Trip details (the ⓘ at the top of a trip, or tap the faces under its
  name): everyone's paid, share and balance side by side, and the settle-up
  payments.
- Tap anyone (in Trip details, Balance or an expense) to see their page:
  photo, UPI ID, totals, who they settle with and their expenses.
- A read-only page for any expense, with the payer's photo, the split and
  the place.

## [1.7.7] - 2026-10-21 (build 30)

### Added
- Delete your account from Profile (at the bottom). After you type DELETE
  and confirm with Google, it removes your TripSplit login, profile,
  nickname, photo and UPI ID, invites, and TripSplit's access to your Google
  account. Expenses you shared stay so everyone's balances still add up,
  shown as "Deleted user". Your Google account itself isn't touched.
  It only works once every trip is settled: while you owe money, or are
  owed money, it lists those trips and asks you to settle up first.
- Tap your name at the top of Profile to change your nickname.

## [1.7.6] - 2026-10-21 (build 29)

### Added
- Pick a nickname after signing in with Google. It's what everyone sees on
  trips, expenses, balances and notifications instead of your Google name;
  your photo and email still come from Google. Change it any time in
  Profile → Nickname. Existing users are asked once too.

### Fixed
- Notifications (the bell) were always empty. They now show the latest
  expenses from all your trips, and say why if they can't load.

## [1.7.5] - 2026-10-21 (build 28)

### Changed
- Adding an expense from a UPI notification now ends with a simple animated
  green tick instead of the roaring lion (no sound).
- Invite emails no longer contain a code. Your friend taps the link,
  installs TripSplit, signs in with Google using the address you invited, and
  is added straight to that trip.

## [1.7.4] - 2026-10-21 (build 27)

### Changed
- The lion is real now. After you add an expense from a UPI notification, a
  real lion bursts out of the pop-up, charges at the screen and roars, then
  blows away like dust as the pop-up closes. (Photo: "Hear me roar" by Adam
  King, CC0.)

## [1.7.3] - 2026-10-20 (build 26)

### Changed
- Invite by email now joins your friend to the trip by itself: once they
  install TripSplit and sign in with the Gmail address you invited, they land
  straight in the trip, with no code to type. The code is still in the email
  in case they use a different Google account.

## [1.7.2] - 2026-10-20 (build 25)

### Added
- Invite by email: tap the invite icon at the top of a trip, type a friend's
  email address and tap "Send invite". Your email app opens with a message
  holding the download link, the trip's invite code and how to join; you tap
  Send. Copying the code is still there too.
- Split an expense between some people, not always everyone: under "Split
  between", untick whoever wasn't part of it. Pick just one person to record
  that you paid on their behalf. Balances follow who was actually included.
- A roaring lion (with sound) when you add an expense from a UPI
  notification. The roar follows your notification volume and stays quiet
  when the phone is on silent.

### Fixed
- Place search on the map picker works again. If it ever fails, it now says
  why instead of showing nothing.
- The category now follows what you type: "Taxi" switches it to Transport
  even after you picked one yourself, and every category (Groceries, Rent,
  Fuel, Shopping, Utilities too) can be picked automatically. In the UPI
  pop-up, your description now counts more than the payee's name.

## [1.7.1] - 2026-10-20 (build 24)

### Changed
- A much smaller download: about 11 MB instead of 53 MB.
- "Scan receipt" now uses Google Play services' text reader, which your phone
  downloads by itself after installing. If you scan a bill in the first minute
  or so, it may ask you to try again shortly.

## [1.7.0] - 2026-10-20 (build 23)

### Changed
- TripSplit no longer runs on a home server. Your trips are kept by Google
  Firebase instead, so "Can't reach the server" should be a thing of the past.
- Works offline: add or edit expenses with no signal and they sync when you're
  back online.
- Live: when a tripmate adds an expense, it appears on your phone right away.
- Updates now download from GitHub.

### Note
- **A fresh start.** Trips from the old server weren't carried over: create
  your trip again, or join one with its new invite code.
- If you're on 1.6.1 or older, this update won't show up in the app. Install it
  once from https://github.com/suddhasattwabanerjee-230808/TripSplit-releases/releases/latest/download/TripSplit.apk
  and later updates arrive in the app as usual.

## [1.6.1] - 2026-10-19 (build 22)

### Changed
- The app now opens straight on your current trip (the last one you opened),
  with the bottom bar. The Home screen is gone: its first tab is now "Trip".
- Switch between trips with "Switch trip" at the top of the trip, or from
  Profile → Your trips.
- Profile now has your trip list with "New trip" and "Join trip", and the
  "UPI payment alerts" switch.
- The notification bell moved to the top of the trip page. For what you owe
  across all trips, use the Balance tab.

## [1.6.0] - 2026-10-19 (build 21)

### Changed
- A brighter, lighter look: a light grey background, white outlined cards, one
  blue accent colour (green and red only for money), thin outline icons and
  plainer titles.
- A bottom bar with five tabs: Home, Add expense, Balance, Statistics, Profile.
- Each trip on Home is its own card, with an icon for its type, its date, how much
  was spent, your balance and the faces of everyone on it.
- On a trip, each expense is its own card, with its date and time, the amount,
  and the faces of the people it's split with.
- A trip opens with a large title, a "Balance summary" card and a "Quick
  operations" row: Balance, Add expense, Scan receipt, View stats.

### Added
- **Pay now.** Tap "Pay" next to anyone you owe and your UPI app opens with their
  UPI ID and the amount filled in. The payment is recorded, so everyone's balance
  updates. Add your own UPI ID in Profile so friends can pay you. "Pay bill now"
  on Home takes you to everything you owe.
- **Scan receipt.** Photograph a bill and the shop name, total, date and category
  are filled in for you. It's read on the phone, so it works offline.
- **Statistics.** Charts of spending over time, by category, by who paid, by city
  and by trip, for all trips or one.
- **Notifications.** The bell on Home lists expenses your tripmates add, with a
  badge for new ones.
- **Trip types** (Trip, Vacation, Roommates, Friends, Couple, Event, Other) and an
  optional start date when you create one.
- **More categories** (Groceries, Rent, Fuel, Shopping, Utilities), plus your own:
  tap "New" when adding an expense. Long-press a custom one to remove it.
- Everyone's profile photo shows across the app, not just yours.
- "See all splits" lists every trip, with search and a filter by type.

## [1.5.0] - 2026-10-19 (build 20)

### Changed
- Sign in with your Google account. No more phone number or OTP code: one tap
  on "Continue with Google" and you're in.
- You stay signed in. The app only signs you out when you tap "Sign out".

### Added
- A profile page (tap your picture at the top of the home screen). It shows
  your photo, name and email, your trip count and overall balance, and the
  app version. You can change the name your tripmates see, check for
  updates, and sign out from here.
- Signed in with a phone number before? Open your profile and tap
  "Connect Google" to keep the same account and all its trips.

## [1.4.5] - 2026-10-17 (build 19)

### Added
- A "UPI payment alerts" switch on the home screen. Turn it off to stop the
  tap-to-add alerts for UPI payments without giving up SMS access, and turn
  it back on any time. If SMS access isn't allowed yet, switching it on
  walks you through allowing it.

This is also the first update you can install straight from the app's
"Update now" button: one progress bar, then the app reopens on the new
version. The very first time, Android may ask you to confirm once.

## [1.4.3] - 2026-10-17 (re-released, build 17)

Rebuilt so that a fresh install from this release has everything below.
It replaces the earlier 1.4.3 builds (11, 13, 14 and 16) and includes all of 1.4.4.

### Changed
- The update pop-up now scrolls, so the "Update now" button stays reachable
  even when the release notes are long (they were pushing it off-screen).
- When you turn on "Auto-add UPI payments", if Android keeps SMS access
  switched off (it does this for apps installed outside the Play Store),
  the app now shows exactly how to allow it — tap the ⋮ menu on the App
  info screen, choose "Allow restricted settings", then turn on SMS. The
  banner clears itself once access is on.
- The app is now signed with its own release certificate instead of the
  Android debug key, so Google Play Protect no longer blocks installing
  the downloaded APK. (You may still see a one-time "install anyway?"
  prompt for an app from outside the Play Store.) Because the signing key
  changed, a device already running an older build must be uninstalled
  and reinstalled once to move onto this version.
- Tapping "Update now" now downloads and installs the update in one go,
  with a single progress bar, and reopens TripSplit on the new version.
  There's no separate "Install?" screen any more. The first update after
  installing this one may still ask once, because Android needs one
  confirmation before an app can update itself silently.
- If Android doesn't allow the app to reopen by itself, a "TripSplit
  updated — tap to open" notification appears instead.
- New app icon: the Gujarat lion emblem replaces the default Flutter logo.
  On Android 13+ it also supports themed (monochrome) icons.
- The UPI payment notification now shows the lion instead of the rupee
  symbol in the status bar, and the full-colour emblem inside the
  notification.
- Saving a UPI expense from the quick-add popup no longer opens the app.
  The popup shows a short success message ("Expense added" and the trip
  name) and closes by itself after 2 seconds.

## [1.4.4] - 2026-10-17

### Changed
- New app icon: the Gujarat lion emblem replaces the default Flutter logo.
  On Android 13+ it also supports themed (monochrome) icons.
- The UPI payment notification now shows the lion instead of the rupee
  symbol in the status bar, and the full-colour emblem inside the
  notification.

## [1.4.2] - 2026-10-16

### Fixed
- The category chips in the UPI quick-add popup now simply fade in when
  you start typing. This removes a deprecated Flutter animation setting
  that was failing the CI analyzer. No other change to how the app works.

## [1.4.1] - 2026-10-16

### Added
- The UPI quick-add popup's location field now has a map button that opens
  the same map picker as the full expense form. You can drag the pin or
  search for a place, and the result fills the location field.

## [1.4.0] - 2026-10-16

### Added
- UPI payment notifications now have **Add** and **Ignore** buttons, so you
  can act on a detected payment straight from the notification shade.
  Ignore just dismisses it.
- The quick-add popup suggests a category (Food, Stay, Transport,
  Activities, Other) as soon as you type a description, and updates the
  guess as you type. Tap a different chip to override it.
- The popup shows the payment's full date and time, and you can tap it to
  change either one.

### Changed
- The popup's location is now an editable field. It's pre-filled with your
  current location, and a button restores that default if you've changed it.
- UPI payments always go to your Gujarat trip, so the popup no longer
  shows a trip picker.
- After you save, the popup closes and TripSplit opens on that trip's
  expense list.

## [1.3.1] - 2026-10-16

### Fixed
- OTA updates were slow and would sometimes hang mid-download. Release
  builds now ship arm64-v8a only instead of bundling armeabi-v7a and
  x86_64 as well, cutting the update download from ~53MB to ~19MB.
  The in-app downloader also resumes a dropped download instead of
  restarting from zero, and gives up and retries a stalled transfer
  instead of hanging indefinitely.

### Added
- The app's version and build number now show as a small label under
  the update icon on the trips list, so it's obvious at a glance
  whether an update actually installed.

## [1.3.0] - 2026-10-16

### Added
- Auto-add UPI payments: when your bank texts a UPI debit alert, the app
  posts a notification with the amount and payee. Tapping it opens a small
  popup (no need to open the full app) to add a description and save it as
  an expense on whichever trip you last had open — amount, date/time, and
  location are filled in automatically. Enabled per-device from a banner on
  the trips list, since it needs SMS access.
- Trip screen and trips list redesigned: your own balance now comes first
  ("You owe ₹X" / "You are owed ₹X"), expenses are grouped by month with a
  running "you lent / you borrowed" per entry computed from your actual
  share, and the overview/balances tab bar is replaced by Settle up /
  Balances / Totals / Invite chips.

## [1.2.0] - 2026-10-14

### Added
- Over-the-air updates: the app checks the TripSplit backend
  (`/releases/latest`) on launch and lets you download + install a newer
  build directly, without going through the Play Store. A manual "check for
  updates" button also lives next to the logout icon on the trips list. The
  release workflow now pushes each tagged build straight to the server after
  creating the GitHub Release.

### Changed
- Location search now calls Google's Places API (New) directly over REST
  (`places:autocomplete` + place details), with the `X-Android-Package`/
  `X-Android-Cert` headers that let an Android-app-restricted key work from
  plain HTTP. Replaces an earlier attempt via the `flutter_google_places_sdk`
  plugin, which only supports the legacy Places API — not enabled (and no
  longer offered) on newer Google Cloud projects.
- Selected search results now show as "Place name, City" (e.g. "Hotel Aditya
  Mansingh, Veraval"), built from the place's own name and address
  components, matching Ola/Uber-style pickers.

### Fixed
- Picking a search result or tapping "recenter" could show the correct
  place/name label for a moment, then have it silently overwritten by a
  plain reverse-geocoded city name — the programmatic camera move those
  actions trigger was firing the same `onCameraIdle` handler used for manual
  map dragging, which re-resolved the label from scratch. Now suppressed for
  camera moves the app itself initiates.

## [1.1.0] - 2026-10-14

### Changed
- Location picker now uses the native Google Maps widget (`google_maps_flutter`)
  instead of OpenStreetMap tiles, for a true Google Maps look and feel —
  same interaction (pin-centered pan-to-select).

### Infrastructure
- Release workflow now writes the Google Maps API key (from a
  `GOOGLE_MAPS_API_KEY` repository secret) into `local.properties` before
  building, so release APKs actually have a working map.
- Debug signing is pinned to a committed `app/debug.keystore` instead of each
  machine's own `~/.android/debug.keystore`, so local and CI builds share one
  signing identity — the SHA-1 the Maps API key is restricted to.

## [1.0.0] - 2026-10-14

First tagged release. Previous history (demo stage) is summarized here
rather than split into pre-1.0 versions.

### Added
- Phone + OTP login, with accounts and sessions backed by a FastAPI server
  (`tripsplit_backend` on the `nav` server, reachable via Tailscale Funnel).
- Trips: create a trip, get a 6-character invite code, others join with it.
  Any number of members per trip (not fixed to 3).
- Expenses: add/edit/delete, always recorded under the logged-in account as
  payer; editing and deleting are restricted to the expense's own creator
  (enforced both client-side and by the backend).
- Each expense carries a category, a pickable date/time, and a location —
  chosen from a full-screen map (OpenStreetMap tiles, pin-centered pan-to-
  select, plus free-text search via Nominatim) or defaulted from GPS.
- Overview screen groups expenses by category and by city, with subtotal
  strips and colored icon badges.
- Balances and suggested settlements, computed server-side per trip.

### Infrastructure
- GitHub Actions CI: `flutter analyze`, `flutter test`, `flutter build apk
  --debug` on every push/PR to `main`.
- GitHub Actions release workflow: pushing a `vX.Y.Z` tag builds a release
  APK and publishes it as a GitHub Release with this changelog's matching
  section as the release notes.
