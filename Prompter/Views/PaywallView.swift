import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var store: ProStore
    @Environment(\.dismiss) private var dismiss

    static let privacyURL = URL(string: "https://github.com/j78fn4wwrs-bit/prompter/blob/main/PRIVACY.md")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Steady Prompter Pro")
                        .font(.largeTitle.bold())
                    Text("One payment. Yours forever. No subscription, no account.")
                        .foregroundStyle(.secondary)
                    feature("video.fill", "Record yourself with the front camera while your script scrolls, saved to Photos")
                    feature("keyboard", "Control with a Bluetooth keyboard or clicker: space to play/pause, arrows to move")
                    feature("paintpalette.fill", "Custom text and background colors")
                    feature("clock.fill", "Estimated read time for every script")

                    if store.isPro {
                        Label("Pro is unlocked. Thank you!", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            Task { await store.purchase() }
                        } label: {
                            Text(store.product.map { "Unlock Pro for \($0.displayPrice)" } ?? "Unlock Pro")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isBusy)

                        Button("Restore Purchase") {
                            Task { await store.restore() }
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(store.isBusy)
                    }

                    if let message = store.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }

                    HStack {
                        Link("Privacy Policy", destination: PaywallView.privacyURL)
                        Spacer()
                        Link("Terms of Use", destination: PaywallView.termsURL)
                    }
                    .font(.footnote)
                    .padding(.top, 8)
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { store.errorMessage = nil }
            .onChange(of: store.isPro) { _, nowPro in
                if nowPro { dismiss() }
            }
        }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 28).foregroundStyle(.tint)
            Text(text)
        }
    }
}
