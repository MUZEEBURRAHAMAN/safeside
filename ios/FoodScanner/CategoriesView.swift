import SwiftUI

/// The Categories tab (Oasis `categories-01`): a clean, instant list of curated
/// category cards. Tap a card → `CategoryDetailView` ("Top rated in {category}",
/// ranked best-first by our own sourced score). Renders from the static
/// `FoodCategory.all` — no load, no spinner.
struct CategoriesView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    // A calm, honest framing line — "top rated" here means our
                    // OWN sourced score, not a lab/agency verdict (principle #1).
                    Text("Browse foods by category, ranked best-first by our transparent score.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    categoryList
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.s45)
                .padding(.top, Theme.Space.s4)
                .padding(.bottom, Theme.Space.s5)
            }
            .background(Theme.canvas)
            .navigationTitle("Categories")
        }
    }

    /// One floating white card (v3 §5.4) holding the category rows with hairline
    /// dividers between them — the Oasis grouped-list shape in SafeSide brand.
    private var categoryList: some View {
        VStack(spacing: 0) {
            ForEach(Array(FoodCategory.all.enumerated()), id: \.element.id) { index, category in
                NavigationLink {
                    CategoryDetailView(category: category)
                } label: {
                    CategoryRow(category: category)
                }
                .buttonStyle(.plain)

                if index < FoodCategory.all.count - 1 {
                    Divider()
                        .background(Theme.border)
                        .padding(.leading, 64) // aligns under the title, past the tile
                }
            }
        }
        .surfaceCard(padded: false)
    }
}

/// One category card row: a soft-green rounded tile with an SF Symbol, the title
/// in Space Grotesk, and a trailing chevron. Purely presentational; the parent
/// `NavigationLink` owns the tap.
private struct CategoryRow: View {
    let category: FoodCategory

    @ScaledMetric(relativeTo: .title3) private var glyph: CGFloat = 22

    var body: some View {
        HStack(spacing: Theme.Space.s3) {
            // TODO(categories-later): replace this SF-Symbol tile with a
            // per-category product photo thumbnail (Oasis shows a real product
            // image). SF Symbol keeps it honest + instant while we have no
            // curated imagery.
            iconTile

            Text(category.title)
                .font(.display(18, weight: .semibold, relativeTo: .title3))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: Theme.Space.s2)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Space.s4)
        .padding(.vertical, Theme.Space.s3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.title). Top rated products.")
        .accessibilityAddTraits(.isButton)
    }

    private var iconTile: some View {
        Image(systemName: category.systemImage)
            .font(.system(size: glyph, weight: .semibold))
            .foregroundStyle(Theme.greenDeep)
            .frame(width: 44, height: 44)
            .background(Theme.greenSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Categories") {
    CategoriesView()
        .environment(SessionService())
}
#endif
