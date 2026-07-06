import XCTest
@testable import RareImageryAPI

final class MobileClaimsTests: XCTestCase {

    func testShouldRefreshWithinWindow() {
        let exp = Int(Date().addingTimeInterval(30).timeIntervalSince1970)
        let claims = MobileClaims(
            sub: "user-uuid",
            aud: "mobile-access",
            exp: exp
        )
        XCTAssertTrue(claims.shouldRefresh(within: 60))
    }

    func testShouldNotRefreshWhenFarFromExpiry() {
        let exp = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let claims = MobileClaims(
            sub: "user-uuid",
            aud: "mobile-access",
            exp: exp
        )
        XCTAssertFalse(claims.shouldRefresh(within: 60))
    }
}
