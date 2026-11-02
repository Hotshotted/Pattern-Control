# Pattern Work on iOS: TestFlight from GitHub

Everything runs on GitHub's macOS runners; you need no Mac. A tag `v1.0.0` (or a manual run) exports the Xcode project with Godot, archives it
with `xcodebuild` using automatic signing through an App Store Connect API key, and uploads the build to TestFlight with `xcrun altool`.
The workflow is `.github/workflows/ios.yml`; the export preset is `iOS` in `export_presets.cfg`.

| Setting | Value |
|---|---|
| Bundle ID | `com.clearpropgames.patternwork` |
| Display name | Pattern Work |
| Devices / orientation | iPhone only, portrait only |
| Minimum iOS | 15.0 |
| Renderer | Compatibility (OpenGL) |
| Status bar | hidden; the screen is kept awake during a shift (and only then) |
| Export compliance | `ITSAppUsesNonExemptEncryption` = false (no non-exempt encryption), so no compliance question on each upload |
| Version / build | the tag (`v1.2.0` is 1.2.0; otherwise 1.0.0) / the commit count (`git rev-list --count HEAD`) |

The workflow reads the exported `Info.plist` and Xcode project back and fails the build if any of the rows above is not true, so the table cannot
drift from what ships.

## 1. What you set up once

### Apple Developer account

1. Join the **Apple Developer Program** (developer.apple.com/programs, 99 USD a year). TestFlight needs it.
2. Note your **Team ID**: developer.apple.com > Account > Membership details > Team ID (10 characters, like `AB12CD34EF`).
3. Optional but tidy: Certificates, Identifiers & Profiles > Identifiers > + > App IDs > App > bundle ID `com.clearpropgames.patternwork`, no
   extra capabilities. (If you skip this, the first signed build registers it for you.)

### App Store Connect

1. appstoreconnect.apple.com > Apps > **+ > New App**: platform iOS, name **Pattern Work** (if the name is taken, pick another: it is only the
   store name, the app on the phone still says Pattern Work), primary language, bundle ID `com.clearpropgames.patternwork`, an SKU
   (`patternwork-ios`), user access Full Access.
2. **Users and Access > Integrations > App Store Connect API > Team Keys > +**: name it `github-ci`, access **Admin** (an *App Manager* key can
   upload builds but cannot create the cloud-managed signing certificate; if the first run stops with a certificate or profile error, use Admin).
   **Download the `.p8` file now: Apple lets you download it once.** Write down the **Key ID** (10 characters) and the **Issuer ID** (a UUID shown
   at the top of that page).

### GitHub secrets

Repository > Settings > Secrets and variables > Actions > New repository secret (or with the `gh` CLI):

| Secret | What it is |
|---|---|
| `APP_STORE_CONNECT_API_KEY_P8` | the whole contents of `AuthKey_XXXXXXXXXX.p8`, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |
| `APP_STORE_CONNECT_KEY_ID` | the Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | the Issuer ID |
| `APPLE_TEAM_ID` | the Team ID |

```
gh secret set APP_STORE_CONNECT_API_KEY_P8 < AuthKey_XXXXXXXXXX.p8
gh secret set APP_STORE_CONNECT_KEY_ID --body "XXXXXXXXXX"
gh secret set APP_STORE_CONNECT_ISSUER_ID --body "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
gh secret set APPLE_TEAM_ID --body "AB12CD34EF"
```

No certificate or provisioning profile is stored anywhere: Xcode asks Apple for them on every run through the API key
(`-allowProvisioningUpdates`). The key is written to the runner's disk for the run and deleted at the end.

## 2. Making a build

* **A release build:** `git tag v1.0.0 && git push origin v1.0.0`. The tag is the version shown in TestFlight; the build number is the commit count, so
  every build is higher than the last as long as there is a new commit between them (a rerun of the same commit uploads the same build number and
  App Store Connect refuses it: push a commit, even an empty one is enough: `git commit --allow-empty -m "build"`).
* **By hand:** GitHub > Actions > *iOS TestFlight* > Run workflow. With **upload** off it exports the project, checks it and compiles it unsigned
  (about 10 minutes, no secrets needed): a check that the iOS build still works. With **upload** on it signs and uploads.
* The run summary shows the version and build. The `.ipa` is kept as a run artifact for 14 days.
* After the upload, App Store Connect "processes" the build for 5 to 30 minutes; it then appears under TestFlight. No export-compliance question
  is asked (the flag is in the app).

## 3. Adding TestFlight testers

* **Internal testers** (up to 100, no review): App Store Connect > Users and Access > add the person with the App Manager, Developer or
  Marketing role, then App > TestFlight > Internal Testing > + > pick them. They get the build as soon as it has processed.
* **Anyone with a link (external testing):** App > TestFlight > **External Testing** > + next to *Groups* > name it `Public beta` > add the
  build. Then open the group > **Enable Public Link** (optionally set a tester limit, up to 10,000) and copy the link. Anyone opening it on an
  iPhone gets the TestFlight app and the beta. The **first build for external testers goes through Beta App Review** (usually under a day;
  later builds of the same version are mostly automatic). Fill the *Test Information* first (below). A build is installable for 90 days.
* To add one person by email instead of a link: the group > Testers > + > Add New Testers.

## 4. Checklist for the first beta review

Do these in App Store Connect before pressing "Submit for review" on the first external build.

- [ ] **Privacy policy URL** (App Information > Privacy Policy URL, and TestFlight > Test Information). It must be a public web page. A draft is in
      section 6 below; put it on any public page (a GitHub Pages page of this repository works) and paste the address.
- [ ] **App Privacy** (App > App Privacy): answer **Data Not Collected**. The app has no account, no analytics, no advertising SDK and makes no
      network request; the save (coins, stars, settings) stays in the app's own storage on the phone. The build also carries a privacy manifest
      (`PrivacyInfo.xcprivacy`: tracking off; the file-timestamp, system-boot-time and disk-space reasons Godot declares).
- [ ] **Test Information** (TestFlight > Test Information): Beta App Description, Feedback Email, Contact (first name, last name, phone, email),
      and **App Review notes** (copy the text in section 5). Sign-in is not required: tick *Sign-in required* off.
- [ ] **What to Test** (per build): a few lines, for example "Play two or three shifts at the Grass Strip and County. Does drawing a path feel right?
      Does anything sit under the notch or the home bar? Does the game pause when a call comes in?"
- [ ] **Age rating**: the questionnaire (App Information > Age Rating): no objectionable content; the aircraft only ever "conflict" as cartoon
      coloured shapes, with no violence, no gambling, no user-generated content, no web access.
- [ ] **Export compliance**: nothing to answer (`ITSAppUsesNonExemptEncryption` is false in the build).
- [ ] **Screenshots** (only for a store listing, not for TestFlight): `docs/store/screenshots/` has five at 1290 x 2796 (the 6.7 and 6.9 inch
      iPhone size). The icon (`docs/store/app-icon-1024.png`) ships inside the build.
- [ ] **Heads-up for the reviewer: the "Watch to double" and "Refund fine" buttons are placeholders.** They show a two-second "Ad playing" screen and
      then give the reward: there is no ad network in the app. Say so in the review notes (section 5). Before a public App Store release,
      either hide them or add a real ad SDK (which changes the privacy answers).
- [ ] No in-app purchases: the coins are earned by playing; nothing is for sale.

## 5. Notes for the reviewer (paste into "App Review notes")

> Pattern Work is a one-finger air traffic control game. No account or sign-in is needed and nothing is collected: the game keeps its save on the
> device and never goes online. To play: tap START SHIFT; aircraft fly in from the screen edges; touch an aircraft and drag a line to the end of
> the runway of the same colour (the runway number shows which end is in use, it follows the wind) and let go. It lands when the line reaches
> the runway. Two aircraft too close together is a conflict (a coin fine). A shift lasts about two minutes and ends on its own; the results card
> shows the stars earned. The airports unlock with stars. The coins are only earned in play; there are no purchases. The "Watch to double" and
> "Refund fine" buttons are placeholders for a future ad: they show a short "Ad playing" screen and give the reward; no ad is loaded. The app
> pauses when it goes to the background or a call comes in and waits for a tap to resume.

## 6. Draft privacy policy (put it on a public page)

> **Privacy policy: Pattern Work** (Clear Prop Games)
>
> Pattern Work does not collect, store on our servers, share or sell any personal information. The game has no accounts and no analytics, shows no
> advertising, and does not connect to the internet. Your progress (coins, stars, settings) is saved only on your device, in the app's own storage,
> and is deleted when you delete the app. If you send us feedback by email, we use the address only to reply to you.
>
> Contact: *your email*. Last updated: *date*.

## 7. If a run fails

| Message | Cause and fix |
|---|---|
| `Missing repository secrets: ...` | the four secrets are not all set (section 1) |
| `No profiles for 'com.clearpropgames.patternwork' were found` or a certificate error in *Archive* | the API key is not Admin, or the key/issuer/team do not match: check all four values; make the key Admin |
| `Unable to authenticate` / `401` in *Upload* | wrong Key ID or Issuer ID, or the `.p8` pasted without its BEGIN/END lines |
| `The bundle version must be higher than the previously uploaded version` | the same commit was built twice: push a new commit and run again |
| `Invalid ... SDK` / "built with an older SDK" | App Store Connect wants a newer Xcode: the workflow picks the newest Xcode on the runner; change `runs-on:` to a newer macOS image |
| *Check the exported Info.plist and project* fails | someone changed the preset or the project settings away from the table at the top of this page |
| Export step: `no ... .xcodeproj` | the iOS export template is missing or a different Godot version: `GODOT_VERSION` in the workflow must match the editor |

## 8. What is verified and what is not

Verified: the export preset by a real project export (Godot 4.5), the plist and project settings in the table, the workflow end to end on a macOS runner
**without signing** (export, the plist checks and an unsigned release build against the iPhone SDK with Xcode 26.3), the pause and haptics and
safe-area behaviour in the smoke tests (`tests/smoke_test.gd`, section 36).

Not verified, because they need your Apple account: the signed archive, the re-sign for the App Store, the upload, and TestFlight processing. The
first signed run is the real test: expect to look at its log once.
