import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var store: ProStore
    @Environment(\.dismiss) private var dismiss
    /// The feature the user tapped, so the sheet explains why it opened.
    var feature: ProFeature = .general

    static let privacyURL = URL(string: "https://j78fn4wwrs-bit.github.io/app-legal/steady-prompter/privacy-policy.html")!
    static let termsURL = URL(string: "https://j78fn4wwrs-bit.github.io/app-legal/steady-prompter/terms-of-use.html")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        LensGlassIconTile(systemName: feature.icon, size: 56, symbolSize: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.headline)
                                .font(.title2.bold())
                                .foregroundStyle(LensGlassColor.label)
                            if feature != .general {
                                Text("Part of Steady Prompter Pro")
                                    .font(.subheadline)
                                    .foregroundStyle(LensGlassColor.secondaryLabel)
                            }
                        }
                    }
                    Text("One payment. Yours forever. No subscription, no account.")
                        .foregroundStyle(LensGlassColor.secondaryLabel)
                    featureRow("video.fill", "Record yourself with the front camera while your script scrolls, saved to Photos")
                    featureRow("keyboard", "Keyboard and clicker control: space to play/pause, arrows for speed and markers, ⌘+/⌘− for text size")
                    featureRow("paintpalette.fill", "Any custom text and background color (the basic presets are free)")
                    featureRow("appletvremote.gen4.fill", "Control this prompter from a second iPhone or iPad nearby (the remote device stays free)")
                    featureRow("clock.fill", "Estimated read time for every script")

                    if store.isPro {
                        Label("Pro is unlocked. Thank you!", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(LensGlassColor.connected)
                    } else {
                        Button {
                            Task { await store.purchase() }
                        } label: {
                            // Primary Lens Glass = near-black text on yellow, readable in both modes.
                            Text(store.product.map { "Unlock Pro for \($0.displayPrice)" } ?? "Unlock Pro")
                        }
                        .buttonStyle(LensGlassButtonStyle(role: .primary, fontSize: 20))
                        .frame(height: 56)
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
                .background(LensGlassColor.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding()
            }
            .background(LensGlassBackground())
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
            LensGlassIconTile(systemName: icon, size: 30, symbolSize: 14)
            Text(text)
                .foregroundStyle(LensGlassColor.label)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
