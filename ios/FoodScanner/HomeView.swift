import SwiftUI

struct HomeView: View {
    @Environment(SessionService.self) private var session
    @Environment(PantryService.self) private var pantryService
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
                    .accessibilityHint("Opens the scanner to scan a barcode.")

                    Text("Recent scans").font(.headline).foregroundStyle(Theme.textPrimary)

                    recentScansSection
                }
                .padding(.horizontal, Theme.Space.s4)
            }
            .background(Theme.canvas)
            .navigationTitle("Home")
            .task(id: session.userID) {
                // Re-runs once the anonymous session's userID resolves
                // (bootstrap is async), and whenever it changes (e.g. later
                // linking with Apple).
                await pantryService.loadRecent()
            }
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

    @ViewBuilder
    private var recentScansSection: some View {
        if pantryService.entries.isEmpty {
            // Empty state (guest-first: works with no account). Loading
            // shows the same calm surface rather than a distracting spinner —
            // the list is small and usually resolves quickly.
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.surface)
                .frame(height: 120)
                .overlay(
                    Text(pantryService.isLoading
                         ? "Loading your pantry…"
                         : "Your pantry's empty — scan your first product.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        .padding()
                )
        } else {
            VStack(spacing: Theme.Space.s3) {
                ForEach(pantryService.entries) { entry in
                    NavigationLink {
                        ProductView(product: entry.asProduct())
                    } label: {
                        PantryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// One pantry row: thumbnail, name, brand, a compact score badge. Mirrors
/// docs/DESIGN_SYSTEM.md §5.4 "Pantry card" — reuses the existing
/// `ScoreBadge(.compact)` (§5.2), which was designed for exactly this dense
/// list context and supplies its own trailing flex space, so it's placed
/// directly after the name/brand group with no extra `Spacer`.
private struct PantryRow: View {
    let entry: PantryEntry

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.s3) {
            ProductThumbnail(urlString: entry.product.images?.bestURL, size: 64)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.product.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if let brand = entry.product.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 96, alignment: .leading)

            ScoreBadge(score: entry.score?.score, band: entry.band)
        }
        .padding(Theme.Space.s3)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityElement(children: .combine)
    }
}
