import AuthenticationServices
import Combine
import Foundation
import Valet


/// A central store for handling authentication.
enum AuthClient {
    
    /// The value of the token used for authentication.
    static func getToken() -> String? {
        AuthClient.cache.token
    }
    
    /// A publisher that tells whether the user is authenticated or not.
    static var state: AnyPublisher<AuthState, Never> {
        AuthClient.cache.$state.eraseToAnyPublisher()
    }
    
    enum AuthState: Equatable {
        case loading
        case authenticated(User)
        case nosession
        case error(String)
    }
    
    // MARK: - Cache
    
    fileprivate static let cache = Cache()
    
    fileprivate class Cache: ObservableObject {
        
        /// The secure valet where we store information about the current user.
        private let valet = Valet.valet(
            with: Identifier(nonEmpty: "com.swiftgraphql.thesocialnetwork")!,
            accessibility: .whenUnlocked
        )
        
        private let encoder = JSONEncoder()
        private let decoder = JSONDecoder()
        
        var token: String? {
            didSet {
                guard let _ = token else {
                    return
                }
                
                NetworkClient.shared.query(User.viewer, policy: .cacheAndNetwork)
                    .receive(on: DispatchQueue.main)
                    .map { res in
                        switch res.result {
                        case .ok(let data) where data != nil:
                            return data
                        default:
                            self.logout()
                            return nil
                        }
                    }
                    .removeDuplicates()
                    .assign(to: &self.$user)
            }
        }
        
        @Published var user: User?
        @Published var state: AuthState
        
        /// Reference to the login task.
        private var login: AnyCancellable?
        
        init() {
            self.token = nil
            self.user = nil
            self.state = .loading
            
            // Update the state as the user changes.
            self.$user
                .map { user in
                    if let user = user {
                        return .authenticated(user)
                    }
                    return .nosession
                }
                .removeDuplicates()
                .assign(to: &self.$state)
        }
        
        /// The structure that the client saves in the Valet.
        private struct Store: Codable {
            static var key: String = "user"
            
            let token: String
        }

        /// Persists the user in the keychain.
        @discardableResult
        private func persist(token: String) -> Bool {
            do {
                let store = Store(token: token)
                let data = try encoder.encode(store)
                try valet.setObject(data, forKey: Store.key)
                
                return true
            } catch {
                return false
            }
        }
        
        // MARK: - Methods
        
        /// Retrieves the token from the keychain.
        func load() {
            self.state = .loading
            guard let data = try? valet.object(forKey: Store.key),
                  let store = try? self.decoder.decode(Store.self, from: data) else {
                self.state = .nosession
                return
            }
            self.token = store.token
        }
        
        /// Authenticates the user and starts relevant services.
        func login(username: String, password: String) {
            self.state = .loading
            
            let auth = User.login(username: username, password: password)
            self.login = NetworkClient.shared.query(auth)
                .receive(on: RunLoop.main)
                .sink(receiveValue: { result in
                    switch result.result {
                    case .ok(let data):
                        // Login the user if we found the token.
                        guard let token = data else {
                            self.logout()
                            return
                        }
                        
                        self.token = token
                        self.persist(token: token)
                    case .error(let errors):
                        self.logout()
                        
                        if let error = errors.first {
                            self.state = .error(error.localizedDescription)
                        }
                    }
                })
        }
        
        /// Removes the user session and logs it out.
        func logout() {
            NetworkClient.cache.clear()
            
            try? valet.removeObject(forKey: Store.key)
            self.token = nil
            self.user = nil
            self.state = .nosession
        }
    }
    
    // MARK: - Methods
    
    /// Authenticates user with username and password.
    static func loginOrSignup(username: String, password: String) {
        cache.login(username: username, password: password)
    }
    
    /// Tries to login user from cache.
    static func loginFromKeychain() {
        cache.load()
    }
    
    /// Removes user cache and stops current session.
    static func logout() {
        cache.logout()
    }
}