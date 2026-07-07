import SwiftUI

/// Signature component. Three redundant signals (number + word + icon) so it's
/// accessible and never relies on colour alone. Non-alarmist by design.
struct ScoreBadge: View {
    let score: Int?
    let band: ScoreBand

    private var color: Color {
        switch band {
        case .high: return Theme.scoreHigh
        case .mid:  return Theme.scoreMid
        case .low:  return Theme.scoreLow
        case .unknown: return Theme.scoreUnknown
        }
    }
    private var icon: String {
        switch band {
        case .high: return "leaf.fill"
        case .mid:  return "circle.lefthalf.filled"
        case .low:  return "exclamationmark.circle"     // informational, not alarmist
        case .unknown: return "questionmark.circle"
        }
    }

    var body: some View {
        HStack(spacing: Theme.Space.s3) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 64, height: 64)
                Text(score.map(String.init) ?? "—")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Label(band.label, systemImage: icon)
                    .font(.headline).foregroundStyle(Theme.textPrimary)
                if let s = score {
                    Text("\(s) / 100").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "Score \($0) of 100, \(band.label)" } ?? band.label)
    }
}

#Preview {
    VStack(spacing: 16) {
        ScoreBadge(score: 82, band: .high)
        ScoreBadge(score: 53, band: .mid)
        ScoreBadge(score: 27, band: .low)
        ScoreBadge(score: nil, band: .unknown)
    }.padding()
}
