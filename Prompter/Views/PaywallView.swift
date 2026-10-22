import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var store: ProStore
    @Environment(\.dismiss) private var dismiss
    /// The feature the user tapped, so the sheet explains why it opened.
    var feature: ProFeature = .general

    static let privacyURL = URL(string: "https://github.com/j78fn4wwrs-bit/prompter/blob/main/PRIVACY.md")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.tint)
                            .frame(width: 56, height: 56)
                            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.headline)
                                .font(.title2.bold())
                            if feature != .general {
                                Text("Part of Steady Prompter Pro")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("One payment. Yours forever. No subscription, no account.")
                        .foregroundStyle(.secondary)
                    featureRow("video.fill", "Record yourself with the front camera while your script scrolls, saved to Photos")
                    featureRow("keyboard", "Keyboard and clicker control: space to play/pause, arrows for speed and markers, ⌘+/⌘− for text size")
                    featureRow("paintpalette.fill", "Any custom text and background color (the basic presets are free)")
                    featureRow("appletvremote.gen4.fill", "Control this prompter from a second iPhone or iPad nearby (the remote device stays free)")
                    featureRow("clock.fill", "Estimated read time for every script")

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

                    #if DEBUG
                    Toggle("Unlock Pro for testing (debug builds only)", isOn: $store.debugUnlock)
                        .font(.footnote)
                    #endif

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

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 28).foregroundStyle(.tint)
            Text(text)
        }
    }
}
