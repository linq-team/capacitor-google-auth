import Capacitor
import Foundation
import GoogleSignIn

/// Please read the Capacitor iOS Plugin Development Guide
/// here: https://capacitor.ionicframework.com/docs/plugins/ios
@objc(GoogleAuth)
public class GoogleAuth: CAPPlugin {
  var signInCall: CAPPluginCall!
  var googleSignIn: GIDSignIn!
  var googleSignInConfiguration: GIDConfiguration!
  var forceAuthCode: Bool = false
  var additionalScopes: [String]!

  func loadSignInClient(
    customClientId: String,
    customScopes: [String]
  ) {
    googleSignIn = GIDSignIn.sharedInstance

    let serverClientId = getServerClientIdValue()

    googleSignInConfiguration = GIDConfiguration.init(
      clientID: customClientId, serverClientID: serverClientId)
    googleSignIn.configuration = googleSignInConfiguration

    // these are scopes granted by default by the signIn method
    let defaultGrantedScopes = ["email", "profile", "openid"]
    // these are scopes we will need to request after sign in
    additionalScopes = customScopes.filter {
      return !defaultGrantedScopes.contains($0)
    }

    forceAuthCode = getConfig().getBoolean("forceCodeForRefreshToken", false)

    NotificationCenter.default.addObserver(
      self, selector: #selector(handleOpenUrl(_:)),
      name: Notification.Name(Notification.Name.capacitorOpenURL.rawValue), object: nil)
  }

  public override func load() {
  }

  @objc
  func initialize(_ call: CAPPluginCall) {
    // get client id from initialize, with client id from config file as fallback
    guard let clientId = call.getString("clientId") ?? getClientIdValue() as? String else {
      NSLog("no client id found in config")
      call.resolve()
      return
    }

    // get scopes from initialize, with scopes from config file as fallback
    let customScopes =
      call.getArray("scopes", String.self) ?? (getConfigValue("scopes") as? [String] ?? [])

    // get force auth code from initialize, with config from config file as fallback
    forceAuthCode =
      call.getBool("grantOfflineAccess")
      ?? (getConfigValue("forceCodeForRefreshToken") as? Bool ?? false)

    // load client
    self.loadSignInClient(
      customClientId: clientId,
      customScopes: customScopes
    )
    call.resolve()
  }

@objc
func signIn(_ call: CAPPluginCall) {
  signInCall = call
  DispatchQueue.main.async {
    if self.googleSignIn.hasPreviousSignIn() && !self.forceAuthCode {
      self.googleSignIn.restorePreviousSignIn { user, error in
        if let error = error {
          self.signInCall?.reject(error.localizedDescription)
          return
        }
        self.resolveSignInCallWith(user: user!)
      }
    } else {
      let presentingVc = self.bridge!.viewController!
      self.googleSignIn.signIn(
        withPresenting: presentingVc, hint: nil, additionalScopes: self.additionalScopes
      ) { response, error in
        if let error = error {
          self.signInCall?.reject(error.localizedDescription, "\(error._code)")
          return
        }
        let user = response!.user
        var userData: [String: Any] = [
          "authentication": [
            "accessToken": user.accessToken.tokenString,
            "idToken": user.idToken?.tokenString ?? "",
            "refreshToken": user.refreshToken.tokenString,
          ],
          "serverAuthCode": response!.serverAuthCode ?? NSNull(),
          "email": user.profile?.email ?? NSNull(),
          "familyName": user.profile?.familyName ?? NSNull(),
          "givenName": user.profile?.givenName ?? NSNull(),
          "id": user.userID ?? NSNull(),
          "name": user.profile?.name ?? NSNull(),
        ]
        if let imageUrl = user.profile?.imageURL(withDimension: 100)?.absoluteString {
          userData["imageUrl"] = imageUrl
        }
        self.signInCall.resolve(userData)
      }
    }
  }
}



  @objc
  func refresh(_ call: CAPPluginCall) {
    DispatchQueue.main.async {
      if self.googleSignIn.currentUser == nil {
        call.reject("User not logged in.")
        return
      }
      let currentUser = self.googleSignIn.currentUser
      if currentUser == nil {
        call.reject("User not logged in.")
        return
      }
      let authenticationData: [String: Any] = [
        "accessToken": currentUser?.accessToken ?? NSNull(),
        "idToken": currentUser?.idToken ?? NSNull(),
        "refreshToken": currentUser?.refreshToken ?? NSNull(),
      ]
      call.resolve(authenticationData)
    }
  }

  @objc
  func signOut(_ call: CAPPluginCall) {
    DispatchQueue.main.async {
      self.googleSignIn.signOut()
    }
    call.resolve()
  }

  @objc
  func handleOpenUrl(_ notification: Notification) {
    guard let object = notification.object as? [String: Any] else {
      print("There is no object on handleOpenUrl")
      return
    }
    guard let url = object["url"] as? URL else {
      print("There is no url on handleOpenUrl")
      return
    }
    googleSignIn.handle(url)
  }

  func getClientIdValue() -> String? {
    if let clientId = getConfig().getString("iosClientId") {
      return clientId
    } else if let clientId = getConfig().getString("clientId") {
      return clientId
    } else if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
      let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject],
      let clientId = dict["CLIENT_ID"] as? String
    {
      return clientId
    }
    return nil
  }

  func getServerClientIdValue() -> String? {
    if let serverClientId = getConfig().getString("serverClientId") {
      return serverClientId
    }
    return nil
  }

  func resolveSignInCallWith(user: GIDGoogleUser) {
    var userData: [String: Any] = [
      "authentication": [
        "accessToken": user.accessToken,
        "idToken": user.idToken,
        "refreshToken": user.refreshToken,
      ],
      //            "serverAuthCode": user.serverAuthCode ?? NSNull(),
      "email": user.profile?.email ?? NSNull(),
      "familyName": user.profile?.familyName ?? NSNull(),
      "givenName": user.profile?.givenName ?? NSNull(),
      "id": user.userID ?? NSNull(),
      "name": user.profile?.name ?? NSNull(),
    ]
    if let imageUrl = user.profile?.imageURL(withDimension: 100)?.absoluteString {
      userData["imageUrl"] = imageUrl
    }
    signInCall?.resolve(userData)
  }
}
