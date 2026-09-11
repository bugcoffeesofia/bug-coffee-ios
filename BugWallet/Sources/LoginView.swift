import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: Session

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorText: String?

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
                        TextField("Email", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    }
                    .textFieldStyle(.plain)
                    .padding()
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: signIn) {
                        if isLoading {
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
                    .disabled(isLoading || email.isEmpty || password.isEmpty)

                    Spacer()
                    Spacer()
                }
                // Stretched across iPhone Duo's inner display the fields get too
                // wide to read comfortably; keep the form phone-sized.
                .frame(maxWidth: 440)
                // TODO(iPhone Duo, iOS 27.1 SDK): centered like this, the form sits
                // right on the fold when the device is folded like a book. Once
                // `reservedRegions(kind:)` ships (it's not in the iOS 27.0 SDK),
                // move it to the trailing half while a fold is present — that's
                // where it ends up when the device closes:
                //
                //     @State private var foldFrames: [CGRect] = []
                //
                //     .frame(maxWidth: .infinity,
                //            alignment: foldFrames.isEmpty ? .center : .trailing)
                //     .onGeometryChange(for: [CGRect].self) { proxy in
                //         proxy.reservedRegions(kind: .division).map(\.frame)
                //     } action: { foldFrames = $0 }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func signIn() {
        errorText = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let account = try await FirebaseAuth.signIn(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password)
                session.account = account
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
