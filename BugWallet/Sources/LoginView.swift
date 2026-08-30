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
