import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var email = ""
    @State private var password = ""
    @State private var showRegister = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Logo area
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 56))
                        .foregroundStyle(.primary)
                    Text("MoreTime")
                        .font(.system(size: 36, weight: .bold, design: .default))
                    Text("AI-powered study scheduling")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .padding()
                        .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                if let error = authStore.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Buttons
                VStack(spacing: 12) {
                    Button {
                        Task { await authStore.login(email: email, password: password) }
                    } label: {
                        if authStore.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Sign In")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primary)
                    .foregroundStyle(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(email.isEmpty || password.isEmpty || authStore.isLoading)

                    Button("Create Account") {
                        showRegister = true
                    }
                    .foregroundStyle(.primary)
                }
                .padding(.horizontal)

                Spacer()
            }
            .sheet(isPresented: $showRegister) {
                RegisterView()
            }
        }
    }
}

struct RegisterView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text("Create Account")
                            .font(.title.bold())
                        Text("Start optimizing your study schedule")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)

                    VStack(spacing: 16) {
                        TextField("Full Name", text: $name)
                            .textContentType(.name)
                            .padding()
                            .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .padding()
                            .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                        SecureField("Password (8+ characters)", text: $password)
                            .textContentType(.newPassword)
                            .padding()
                            .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                        SecureField("Confirm Password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .padding()
                            .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)

                    if let error = authStore.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    Button {
                        Task {
                            await authStore.register(email: email, name: name, password: password)
                            if authStore.isAuthenticated { dismiss() }
                        }
                    } label: {
                        if authStore.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Create Account")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primary)
                    .foregroundStyle(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(!passwordsMatch || name.isEmpty || email.isEmpty || password.count < 8 || authStore.isLoading)
                    .padding(.horizontal)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
