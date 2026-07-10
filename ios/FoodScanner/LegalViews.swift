import SwiftUI

// =============================================================================
// Legal & attribution surfaces (Chunk 7) — Me tab.
//
// ⚠️ LEGAL REVIEW REQUIRED before ship. The Privacy Policy and Terms *bodies*
// below are DRAFTS written in the COPY_DECK voice (calm, plain-language, no
// dark patterns) — they are NOT reviewed legal copy. They disclose analytics
// honestly (ANALYTICS_METRICS §8: no third-party ad/tracking SDKs, data
// minimization, guest-first, events/app_feedback usage) and keep the standard
// health disclaimer, but a founder/legal pass is a merge/ship gate. The same
// text is mirrored in docs/COPY_DECK.md §Legal bodies (Chunk 7).
//
// Attribution copy IS verbatim from COPY_DECK §Legal & attribution (reviewed).
// All screens use DESIGN_SYSTEM_V3 tokens — no boilerplate legal-wall look
// (teardown AVOID #12).
// =============================================================================

/// One titled block of body paragraphs — the shared shape for the drafted
/// Privacy/Terms bodies so both screens render on identical tokens.
private struct LegalSection: Identifiable {
    let id = UUID()
    let title: String
    let paragraphs: [String]
}

/// Shared scaffold: light canvas, section cards, a footer disclaimer, and a
/// "Close" toolbar — matches the Result/About sheet language, not a legal wall.
private struct LegalScreen<Footer: View>: View {
    let navigationTitle: String
    let intro: String?
    let sections: [LegalSection]
    @ViewBuilder let footer: () -> Footer

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s5) {
                if let intro {
                    Text(intro)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(sections) { section in
                    SectionCard {
                        VStack(alignment: .leading, spacing: Theme.Space.s2) {
                            Text(section.title)
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                footer()
            }
            .padding(Theme.Space.s4)
        }
        .background(Theme.canvas)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .foregroundStyle(Theme.greenDeep)
            }
        }
    }
}

/// Standard health/allergen disclaimer (COPY_DECK §Settings & account footer) —
/// reused across the legal screens.
private struct LegalDisclaimerFooter: View {
    var body: some View {
        Text("Information only — not medical advice. Allergen data may be incomplete; check labels.")
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Privacy Policy

/// DRAFT — see the file header. Discloses analytics per ANALYTICS_METRICS §8.
struct PrivacyPolicyView: View {
    // NOTE: DRAFT copy — LEGAL REVIEW REQUIRED. Mirrored in COPY_DECK.
    private let intro = "Short version: you can use SafeSide as a guest, we collect as little as we can, and we never sell your data."

    private let sections: [LegalSection] = [
        LegalSection(
            title: "You're a guest by default",
            paragraphs: [
                "Nothing is required to scan a product and see its score. You can use the app without an account or sharing your name.",
                "If you answer the optional setup questions, that's to make suggestions fit you — every question is skippable.",
            ]
        ),
        LegalSection(
            title: "What we store",
            paragraphs: [
                "The things that make the app work: your profile answers, the products you scan, your pantry and favorites, and any plans you build.",
                "This is tied to a random, pseudonymous account id — not your name or email.",
            ]
        ),
        LegalSection(
            title: "Analytics we keep",
            paragraphs: [
                "We log a small set of in-app events — for example, that a scan started or a score was viewed — so we can see where the app helps and where people get stuck.",
                "These events carry only your pseudonymous id plus simple values like a score band or a product id. They never include the text you type, your photos, or anything read off a label.",
                "We don't use third-party ad or tracking SDKs, and we don't sell or share your data with advertisers.",
            ]
        ),
        LegalSection(
            title: "Feedback you send",
            paragraphs: [
                "If you send feedback through the app, your message is stored separately from analytics and read only by our team, to help us fix things.",
            ]
        ),
        LegalSection(
            title: "Your control",
            paragraphs: [
                "You stay a guest until you choose otherwise. A control to clear your on-device data is on the way, and you'll be able to ask us to delete your account data.",
                "Questions about your data? Reach us at privacy@safeside.app.",
            ]
        ),
    ]

    var body: some View {
        LegalScreen(navigationTitle: "Privacy policy", intro: intro, sections: sections) {
            LegalDisclaimerFooter()
        }
    }
}

// MARK: - Terms of use

/// DRAFT — see the file header. LEGAL REVIEW REQUIRED.
struct TermsView: View {
    private let intro = "Short version: SafeSide gives you clear, sourced information about food — it's not medical advice."

    private let sections: [LegalSection] = [
        LegalSection(
            title: "Information, not advice",
            paragraphs: [
                "Scores and explanations are for general information. They're not medical, nutritional, or health advice, and they're not a diagnosis.",
                "For decisions about your health or diet, talk to a qualified professional. Always check the actual product label, especially for allergens.",
            ]
        ),
        LegalSection(
            title: "About the data",
            paragraphs: [
                "Product details come from open databases and public sources. They can be incomplete or out of date, and we can't guarantee every detail is correct.",
                "If something looks wrong, use \"Report an issue\" on the product — it helps us and everyone else.",
            ]
        ),
        LegalSection(
            title: "Using the app",
            paragraphs: [
                "SafeSide is for your personal, non-commercial use. Please don't misuse the service, try to break it, or scrape it.",
            ]
        ),
        LegalSection(
            title: "Changes",
            paragraphs: [
                "We may update the app and these terms as SafeSide grows. If a change is significant, we'll do our best to make it clear. Continuing to use the app means you accept the current terms.",
                "Questions? Reach us at hello@safeside.app.",
            ]
        ),
    ]

    var body: some View {
        LegalScreen(navigationTitle: "Terms of use", intro: intro, sections: sections) {
            LegalDisclaimerFooter()
        }
    }
}

// MARK: - Data sources & attribution

/// Attribution — copy VERBATIM from COPY_DECK §Legal & attribution. Open Food
/// Facts is ODbL (attribution + share-alike on the data); USDA FoodData Central
/// is public domain.
struct AttributionView: View {
    @Environment(\.dismiss) private var dismiss

    private var openFoodFactsURL: URL? { URL(string: "https://world.openfoodfacts.org") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s5) {
                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Space.s2) {
                        Text("Open Food Facts")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        // VERBATIM — COPY_DECK §Legal & attribution intro.
                        Text("Product data comes from Open Food Facts, available under the Open Database License (ODbL).")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let openFoodFactsURL {
                            Link("world.openfoodfacts.org", destination: openFoodFactsURL)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.greenDeep)
                        }
                        // ODbL share-alike note.
                        Text("Under the ODbL we attribute the data and share alike — improvements to the data stay open.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Space.s2) {
                        Text("USDA FoodData Central")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        // VERBATIM — COPY_DECK §Legal & attribution USDA line.
                        Text("Nutrition enrichment from USDA FoodData Central (public domain).")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                LegalDisclaimerFooter()
            }
            .padding(Theme.Space.s4)
        }
        .background(Theme.canvas)
        .navigationTitle("Data sources & attribution")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .foregroundStyle(Theme.greenDeep)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Privacy policy") { NavigationStack { PrivacyPolicyView() } }
#Preview("Terms of use") { NavigationStack { TermsView() } }
#Preview("Attribution") { NavigationStack { AttributionView() } }
#endif
