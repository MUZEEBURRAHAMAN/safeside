import Testing
@testable import FoodScanner

/// The curated `FoodCategory.all` list is hand-maintained and maps human titles
/// to REAL Open Food Facts `categories_tags`. These invariants keep the mapping
/// honest: every card resolves to at least one real tag, tags are well-formed
/// `en:` slugs (so the `categories_tags && {…}` overlap query can match), and
/// ids are unique (they back `ForEach`/navigation identity).
@Suite("FoodCategory curated list")
struct FoodCategoryTests {

    @Test("Every category maps to at least one OFF tag")
    func everyCategoryHasATag() {
        for category in FoodCategory.all {
            #expect(!category.offTags.isEmpty, "\(category.id) has no offTags")
        }
    }

    @Test("Tags are lowercase en: slugs")
    func tagsAreWellFormed() {
        for category in FoodCategory.all {
            for tag in category.offTags {
                #expect(tag.hasPrefix("en:"), "\(tag) is not an en: slug")
                #expect(tag == tag.lowercased(), "\(tag) is not lowercase")
                #expect(!tag.contains(" "), "\(tag) contains a space")
            }
        }
    }

    @Test("Category ids are unique")
    func idsAreUnique() {
        let ids = FoodCategory.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Titles are non-empty")
    func titlesArePresent() {
        for category in FoodCategory.all {
            #expect(!category.title.isEmpty)
        }
    }
}
