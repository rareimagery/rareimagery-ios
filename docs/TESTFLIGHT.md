# TestFlight — Ship RareImagery iOS

Native SwiftUI app (`com.rareimagery.studio`). **Not Expo** — distribution is via Xcode + App Store Connect TestFlight.

| Property | Value |
|----------|-------|
| Bundle ID | `com.rareimagery.studio` |
| Team ID | `7ZGZLG2SRQ` |
| ASC App ID | `6771493728` |
| CI scheme | `RareImageryStudio` |
| Export plist | [`ExportOptions.plist`](../ExportOptions.plist) |

---

## Path A: Xcode Cloud (recommended)

### One-time setup (App Store Connect)

1. Open [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → RareImagery.
2. **Xcode Cloud** (or Xcode → Product → Xcode Cloud → Manage Workflows).
3. Create or verify a workflow:
   - **Repository:** `rareimagery/rareimagery-ios`
   - **Branch:** `main` (merge PR first)
   - **Scheme:** `RareImageryStudio`
   - **Environment variable:** `X_CLIENT_ID` = your X OAuth 2.0 Client ID (public, from [X developer portal](https://developer.x.com/en/portal/dashboard))
   - **Archive** post-action: **TestFlight Internal Testing**

[`ci_scripts/ci_post_clone.sh`](../ci_scripts/ci_post_clone.sh) runs `xcodegen generate` and writes `Configuration/Release.local.xcconfig` from `X_CLIENT_ID` when set.

### Trigger a build

- Push to the workflow branch, or
- Xcode → Product → Xcode Cloud → **Start Build**

Builds appear under **TestFlight → Builds** after the Archive post-action completes.

---

## Path B: Manual Archive (fallback)

### Prerequisites

- Xcode signed in with Apple ID on team `7ZGZLG2SRQ`
- `Configuration/Release.local.xcconfig` with real `X_CLIENT_ID` (gitignored; copy from [`Debug.local.xcconfig.example`](../Configuration/Debug.local.xcconfig.example))
- X app callback URL: `rareimagery://auth/callback`

### Steps

1. Open `RareImagery.xcodeproj` in Xcode.
2. Scheme **RareImagery**, destination **Any iOS Device (arm64)**.
3. **Product → Archive** (Release).
4. Organizer → **Distribute App** → **App Store Connect** → **Upload**.
5. Automatic signing, team `7ZGZLG2SRQ`.

### Install on device

1. App Store Connect → **TestFlight** → Internal Testing → add testers.
2. Install **TestFlight** on iPhone → accept invite → install RareImagery.

---

## Verify before shipping

```bash
swift test --package-path Packages/RareImageryAPI
xcodebuild -project RareImagery.xcodeproj -scheme RareImagery \
  -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build
```

Manual QA on TestFlight build:

- [ ] Sign in → kill app → reopen (stays signed in, not anonymous funnel)
- [ ] X OAuth completes on device
- [ ] OnePageCreator or funnel happy path reaches BFF

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| X sign-in fails on TestFlight | Set `X_CLIENT_ID` in Release.local.xcconfig or Xcode Cloud env |
| Xcode Cloud: scheme not found | Use `RareImageryStudio`; shared scheme must be committed |
| OAuth redirect error | Register `rareimagery://auth/callback` in X developer portal |
| Build uses placeholder client ID | CI log should show `wrote Configuration/Release.local.xcconfig` |
