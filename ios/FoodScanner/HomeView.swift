import SwiftUI

struct HomeView: View {
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s5) {
                    Text("What's really in your food?")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, Theme.Space.s4)

                    // Primary action: Scan
                    Button { showScanner = true } label: {
                        HStack {
                            Image(systemName: "barcode.viewfinder").font(.title2)
                            Text("Scan a product").font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(Theme.onGreen)
                        .background(Theme.greenDeep)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }

                    Text("Recent scans").font(.headline).foregroundStyle(Theme.textPrimary)
                    // Empty state (guest-first: works with no account)
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Theme.surface)
                        .frame(height: 120)
                        .overlay(
                            Text("Your pantry's empty — scan your first product.")
                                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                                .padding()
                        )
                }
                .padding(.horizontal, Theme.Space.s4)
            }
            .background(Theme.canvas)
            .navigationTitle("Home")
            .fullScreenCover(isPresented: $showScanner) {
                NavigationStack {
                    ScanScreen()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showScanner = false }
                            }
                        }
                }
            }
        }
    }
}
