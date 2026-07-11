import SwiftUI

/// "Top rated · {category}" (Oasis `list-01`): the category's products ranked
/// best-first by OUR own sourced score. Loads via `CategoryService` on `.task`.
///
/// Honesty: "top rated" = highest on our transparent, sourced score — NOT a lab
/// or agency verdict (there is deliberately no "Lab tested" / "Proven by N
/// agencies" badge here; we hold no such data — CLAUDE.md principle #1, teardown
/// AVOID list). Only high-confidence, current-version scores are ranked, so the
/// list is honest about what we actually know.
struct CategoryDetailView: View {
    let category: FoodCategory

    @Environment(SessionService.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var state: CategoryService.State = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                // TODO(categories-later): sub-category filter chips (Oasis
                // "All / Bottled Water / Flavored Water"). Needs a sub-taxonomy
                // we don't have — left off until then.
                // filterChips

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.s45)
            .padding(.top, Theme.Space.s4)
            .padding(.bottom, Theme.Space.s5)
        }
        .background(Theme.canvas)
        .navigationTitle("Top rated")
        .navigationBarTitleDisplayMode(.inline)
        // Keyed on userID (like Home's trending load) so it also re-runs once
        // guest bootstrap resolves — plus on category.id for safety. `.task`
        // re-fires when either changes.
        .task(id: session.userID + category.id) { await load() }
    }

    private func load() async {
        state = .loading
        let service = CategoryService(session: session)
        await service.loadProducts(for: category)
        state = service.state
    }

    @ViewBuilder
    private var content: some View {
        Text("Top rated · \(category.title)")
            .font(DisplayType.h1)
            .foregroundStyle(Theme.textPrimary)
            .accessibilityAddTraits(.isHeader)

        switch state {
        case .idle, .loading:
            loadingList
        case .loaded(let rows):
            if rows.isEmpty {
                emptyState
            } else {
                rankedList(rows)
            }
        case .error:
            errorState
        }
    }

    // MARK: Ranked list

    // TODO(categories-later): gate the top N results behind the paywall (Oasis
    // blurs the best rows behind "Unlock top rated"). No paywall until Phase D
    // (RevenueCat) — every ranked product is shown in full for now.
    private func rankedList(_ rows: [CategoryProductRow]) -> some View {
        VStack(spacing: Theme.Space.s2) {
            ForEach(rows) { row in
                if let barcode = row.barcode {
                    NavigationLink {
                        ProductLoaderView(barcode: barcode)
                    } label: {
                        CategoryProductRowView(row: row)
                    }
                    .buttonStyle(.plain)
                } else {
                    // No barcode ⇒ can't route to the scored path; show it
                    // (still ranked) but non-tappable rather than dead-linking.
                    CategoryProductRowView(row: row)
                }
            }
        }
    }

    // MARK: States

    private var loadingList: some View {
        VStack(spacing: Theme.Space.s3) {
            ForEach(0..<5, id: \.self) { _ in
                CategoryRowSkeleton()
            }
        }
        .accessibilityLabel("Loading top rated products")
    }

    /// Honest, never-a-dead-end empty state (principle #4): a calm line + a Scan
    /// action, never a spinner-forever. Category lists are genuinely thin until
    /// more products are scored.
    private var emptyState: some View {
        VStack(spacing: Theme.Space.s3) {
            Image(systemName: "tray")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text("No scored products here yet")
                .font(DisplayType.h2)
                .foregroundStyle(Theme.textPrimary)
            Text("Scan one and we'll start the list for \(category.title.lowercased()).")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Scan a product") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.greenDeep)
                .frame(minHeight: 44)
                .padding(.top, Theme.Space.s1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.s6)
    }

    private var errorState: some View {
        VStack(spacing: Theme.Space.s3) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text("Couldn't load this category")
                .font(DisplayType.h2)
                .foregroundStyle(Theme.textPrimary)
            Text("That didn't load right. Give it a moment and try again.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") { Task { await load() } }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.greenDeep)
                .frame(minHeight: 44)
                .padding(.top, Theme.Space.s1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.s6)
    }
}

// MARK: - Ranked product row

/// One ranked row (Oasis `list-01`): a rounded product thumbnail, the name
/// (Space Grotesk, up to 2 lines), a muted brand meta line, a sourced "Scored"
/// chip, and a trailing compact `ScoreBadge` ring. Every row here holds our own
/// current-version score (the ranker drops everything else), so the chip + ring
/// always reflect a real, sourced verdict. Purely presentational.
private struct CategoryProductRowView: View {
    let row: CategoryProductRow

    private var accessibilityText: String {
        var parts = [row.name]
        if let brand = row.brand, !brand.isEmpty { parts.append(brand) }
        parts.append("Score \(row.score) of 100, \(row.band.label)")
        parts.append("Opens product details.")
        return parts.joined(separator: ". ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s3) {
            ProductThumbnail(urlString: row.imageURL, size: 56)

            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text(row.name)
                    .font(.display(17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let brand = row.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                scoredChip

                // SCAFFOLD — renders nothing (verifiedBy is always empty). See
                // Agency / VerifiedByBadge. Never a fabricated agency claim.
                VerifiedByBadge(agencies: row.verifiedBy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScoreBadge(score: row.score, band: row.band, diameter: 52, lineWidth: 5)
        }
        .padding(.vertical, Theme.Space.s2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    /// Sourced "Scored" chip — same transparency affordance as the Search rows:
    /// it means "we hold our OWN current-version score", never OFF's Nutri-Score.
    private var scoredChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("Scored")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Theme.greenDeep)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.greenSoft, in: Capsule())
    }
}

/// SCAFFOLD (categories-later) — the data-driven "Verified by {agencies}" badge.
/// Renders NOTHING while `agencies` is empty, which it always is for now (we
/// hold no multi-agency lab dataset; fabricating one violates principle #1). It
/// flips on automatically if `CategoryProductRow.verifiedBy` is ever populated
/// from a real source — no rewrite, and no false claim shown in the meantime.
struct VerifiedByBadge: View {
    let agencies: [Agency]

    var body: some View {
        if agencies.isEmpty {
            EmptyView()
        } else {
            // TODO(categories-later): design the real badge when a sourced
            // dataset exists. Deliberately minimal + unreachable for now.
            Text("Verified by \(agencies.map(\.name).joined(separator: ", "))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.greenDeep)
        }
    }
}

/// Calm loading placeholder row (matches the ranked-row silhouette).
private struct CategoryRowSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s3) {
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Theme.surfaceAlt)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceAlt).frame(height: 16)
                RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceAlt).frame(width: 120, height: 12)
            }
            Spacer(minLength: 0)
            Circle().fill(Theme.surfaceAlt).frame(width: 52, height: 52)
        }
        .padding(.vertical, Theme.Space.s2)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Category detail") {
    NavigationStack {
        CategoryDetailView(category: FoodCategory.all[0])
    }
    .environment(SessionService())
}
#endif
