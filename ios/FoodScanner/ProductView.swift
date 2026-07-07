import SwiftUI

/// Product result: score badge + "why this score" (sourced) + ingredients.
/// Never a dead-end — always offers a next action. Stubbed for Phase 0.
struct ProductView: View {
    let product: Product

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                Text(product.name).font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                if let brand = product.brand {
                    Text(brand).font(.subheadline).foregroundStyle(Theme.textSecondary)
                }

                if let score = product.score {
                    ScoreBadge(score: score.score, band: score.band)
                        .padding().background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                    // "Why this score" — sourced factors, dose-aware. Transparency = trust.
                    DisclosureGroup("Why this score") {
                        ForEach(score.factors) { f in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(f.name).font(.subheadline.bold())
                                    Spacer()
                                    Text("\(f.subScore)/100 · \(Int(f.weight*100))%")
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Text(f.detail).font(.footnote).foregroundStyle(Theme.textSecondary)
                                if let src = f.sources.first {
                                    Text("Source: \(src.name)").font(.caption2)
                                        .foregroundStyle(Theme.green)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .tint(Theme.greenDeep)

                    if score.confidence == "limited" {
                        Text("Based on partial data").font(.caption)
                            .foregroundStyle(Theme.scoreMid)
                    }
                } else {
                    ScoreBadge(score: nil, band: .unknown)
                }

                // Next action — never a dead-end
                Button("See a better option") { /* TODO: swaps */ }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(Theme.onGreen).background(Theme.greenDeep)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                Text("Ingredients").font(.headline).foregroundStyle(Theme.textPrimary)
                ForEach(product.ingredients) { ing in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ing.name).font(.subheadline.bold())
                        if let what = ing.what { Text(what).font(.footnote).foregroundStyle(Theme.textSecondary) }
                    }.padding(.vertical, 4)
                }

                Text("Data from Open Food Facts").font(.caption2).foregroundStyle(Theme.textSecondary)
                Text("Information only — not medical advice.").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.Space.s4)
        }
        .background(Theme.canvas)
    }
}
