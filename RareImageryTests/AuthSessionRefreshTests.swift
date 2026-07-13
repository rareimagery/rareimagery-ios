import XCTest
@testable import RareImagery
import RareImageryAPI

@MainActor
final class AuthSessionRefreshTests: XCTestCase {

    func testApplyRefreshPreservesOnboardingFlags() {
        let session = AuthSession()
        session.hasSeenLivePreview = true
        session.hasSeenFunnel = true

        let exp = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let claims = MobileClaims(
            sub: "user-uuid",
            storeUuid: "store-uuid",
            slug: "tester",
            handle: "tester",
            role: "CREATOR",
            aud: "mobile-access",
            exp: exp
        )
        let tokens = AuthTokenResponse(
            accessToken: "token",
            refreshToken: "refresh",
            expiresIn: 3600
        )

        session.applyRefresh(tokens: tokens, claims: claims)

        XCTAssertTrue(session.isSignedIn)
        XCTAssertTrue(session.hasSeenLivePreview)
        XCTAssertTrue(session.hasSeenFunnel)
        XCTAssertNil(session.lastError)
    }
}
