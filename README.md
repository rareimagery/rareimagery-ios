# RareImagery (iOS, SwiftUI)

Native iOS client for RareImagery Studio. Thin client over the Next.js + Drupal BFF at `https://www.rareimagery.net`.

## Build

```bash
# Generate the Xcode project from project.yml (rerun any time you add/remove a Swift file)
xcodegen generate

# Open in Xcode
open RareImagery.xcodeproj

# Or build/run on simulator from the CLI:
xcodebuild -project RareImagery.xcodeproj \
  -scheme RareImagery \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build
```

## Required configuration

Edit the xcconfigs before first build:

- `Configuration/Debug.xcconfig` — set `X_CLIENT_ID` to your X (Twitter) dev portal Client ID. Defaults `API_BASE_URL` at `http://localhost:3000` for local Next.js.
- `Configuration/Release.xcconfig` — set `X_CLIENT_ID` for production. `API_BASE_URL` defaults to `https://www.rareimagery.net`.

The X OAuth redirect URI registered in the X developer portal MUST be `rareimagery://auth/callback`.

## Architecture

- `Packages/RareImageryAPI/` — local Swift Package. All networking, auth, models, repositories live here.
  - `Client/` — `APIClient` (actor), `APIError`, `HTTPMethod`, `APIConfiguration`, `APIEndpoint`
  - `Auth/` — `PKCE`, `KeychainStore` (actor), `JWTDecoder`, `TokenRefresher`, `AuthService`
  - `Models/` — `AuthTokenResponse`, `MobileClaims`, `MobileErrorResponse`
  - `Repositories/` — `AuthRepository` (more added in Phase B/C)
- `RareImagery/` — app target
  - `RareImageryApp.swift` — `@main`, `onOpenURL` handler
  - `ContentView.swift` — routes between `SignInView` and signed-in placeholder based on `AuthSession.status`
  - `Auth/` — `SignInView` (SwiftUI) + `AuthCoordinator` (ASWebAuthenticationSession bridge)
  - `State/` — `AppState` (root container) + `AuthSession` (`@Observable`)
  - `Theme/` — `Colors` (#0a0a0a bg, #7c3aed accent), `Typography`

Zero third-party Swift dependencies. Apple frameworks only.

## Tests

```bash
swift test --package-path Packages/RareImageryAPI
```

Currently covers PKCE + JWTDecoder. Expanded in Phase D.

## Phases

- **A — Auth + skeleton (in progress).** SignInView → X OAuth → Keychain token storage → signed-in placeholder.
- **B — Capture + upload.** AVFoundation camera, multi-shot filmstrip with hero selection, multipart upload, Grok Vision call returning `ProductDraft`.
- **C — Draft review + publish.** Edit title/desc/price, PATCH to BFF, POST publish, render storefront URL.
- **D — Polish + tests + ship.** Snapshot tests, README polish, archive, upload to TestFlight (asc app id `6771493728`).

## TestFlight

App Store Connect record already exists from prior Expo work:
- Apple ID: `rare@rareimagery.net`
- Team ID: `7ZGZLG2SRQ`
- asc App ID: `6771493728`
- Bundle ID: `com.rareimagery.studio`
- Universal Links: `applinks:rareimagery.net`, `applinks:*.rareimagery.net`

For Phase D upload: `Product > Archive` in Xcode → Distribute App → App Store Connect.

See [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md) for Xcode Cloud CI setup (`RareImageryStudio` scheme, `X_CLIENT_ID` env var) and manual Archive steps.

## Anti-patterns (per `CLAUDE.md` in the BFF monorepo)

- ❌ Re-implementing Grok Vision logic locally (server handles)
- ❌ Drupal entity writes from the client (use BFF endpoints)
- ❌ JWT signing (client only decodes; server-only signing)
- ❌ Third-party state libs (use `@Observable`)
- ❌ Combine — use async/await
