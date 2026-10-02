import SwiftUI

/// The login form's state and the sign-in round trip, kept out of the view so
/// it can be unit tested without a network or a screen.
@MainActor
final class LoginModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var errorText: String?

    private let authenticate: (String, String) async throws -> Account

    init(authenticate: @escaping (String, String) async throws -> Account = {
        try await FirebaseAuth.signIn(email: $0, password: $1)
    }) {
        self.authenticate = authenticate
    }

    var canSubmit: Bool { !isLoading && !email.isEmpty && !password.isEmpty }

    func signIn(into session: Session) async {
        errorText = nil
        isLoading = true
        defer { isLoading = false }
        do {
            session.account = try await authenticate(
                email.trimmingCharacters(in: .whitespaces), password)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var session: Session
    @StateObject private var model: LoginModel

    /// `model` is a seam for tests; the app lets the view make its own.
    init(model: LoginModel? = nil) {
        _model = StateObject(wrappedValue: model ?? LoginModel())
    }

    /// The trailing edge of the fold when the device is folded like a book;
    /// 0 when it's flat (iOS 27.1+).
    @State private var foldTrailingEdge: CGFloat = 0

    private let brand = Color(red: 31/255, green: 4/255, blue: 9/255)
    private let accent = Color(red: 204/255, green: 30/255, blue: 65/255)

    var body: some View {
        ZStack {
            brand.ignoresSafeArea()
            // Scrolls when the keyboard or a short window leaves too little
            // height for the form, instead of squeezing it.
            FittingScrollView { _ in
                VStack(spacing: 24) {
                    Spacer()

                    Text("Bug Coffee")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Sign in to show your loyalty card")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))

                    VStack(spacing: 12) {
                        TextField("Email", text: $model.email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        SecureField("Password", text: $model.password)
                            .textContentType(.password)
                    }
                    .textFieldStyle(.plain)
                    .padding()
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    if let errorText = model.errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: signIn) {
                        if model.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Sign In").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(accent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal)
                    .disabled(!model.canSubmit)

                    Spacer()
                    Spacer()
                }
                // Stretched across iPhone Duo's inner display the fields get too
                // wide to read comfortably; keep the form phone-sized.
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
                // Folded like a book, a centered form would sit on the crease,
                // so the leading half is padded away and the form centers in
                // the trailing half — where it ends up when the device closes.
                .padding(.leading, foldTrailingEdge)
            }
        }
        .onVerticalFoldChange { foldTrailingEdge = $0 }
    }

    private func signIn() {
        Task { await model.signIn(into: session) }
    }
}
