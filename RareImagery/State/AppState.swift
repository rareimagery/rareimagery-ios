import Foundation
import RareImageryAPI

/// Root composition container — wires up SPM services and exposes them to SwiftUI.
@MainActor
@Observable
final class AppState {
    let configuration: APIConfiguration
    let keychain: KeychainStore
    let client: APIClient
    let authRepository: AuthRepository
    let authService: AuthService
    let uploadRepository: UploadRepository
    let productRepository: ProductRepository
    let session: AuthSession
    let capture: CaptureSession

    init() {
        self.configuration = APIConfiguration.fromBundle
        let keychain = KeychainStore()
        self.keychain = keychain
        let client = APIClient(configuration: configuration, keychain: keychain)
        self.client = client
        self.authRepository = AuthRepository(client: client)
        self.authService = AuthService(configuration: configuration, repository: authRepository, client: client)
        self.uploadRepository = UploadRepository(client: client)
        self.productRepository = ProductRepository(client: client)
        self.session = AuthSession()
        self.capture = CaptureSession()
    }

    /// Called once on app launch — see if we already have a valid access token in the Keychain.
    func bootstrap() async {
        do {
            if let access = try await keychain.get(.accessToken) {
                let claims = try JWTDecoder.decode(access)
                session.status = .signedIn(claims)
                return
            }
        } catch {
            // fall through to signedOut
        }
        session.setSignedOut()
    }

    func signOut() async {
        do { try await authService.signOut() } catch { session.setError("Sign-out failed: \(error)") }
        session.setSignedOut()
        capture.reset()
    }

    #if DEBUG
    /// Bypass real OAuth for capture-flow testing without a backend.
    /// Synthesizes a fake MobileClaims envelope and flips session to signedIn.
    func debugSimulateSignIn() {
        let now = Int(Date().timeIntervalSince1970)
        let claims = MobileClaims(
            sub: "debug-user",
            storeUuid: "debug-store",
            slug: "debug",
            handle: "debug_user",
            role: "x_creator",
            aud: MobileClaims.expectedAudience,
            exp: now + 3600,
            iat: now
        )
        session.status = .signedIn(claims)
    }
    #endif
}
