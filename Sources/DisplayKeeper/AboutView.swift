import AppKit
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: AppInfo.icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 112, height: 112)
                .padding(.top, 8)
            Text("Display Keeper")
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 6)
            Text(AppInfo.versionDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)
            Text("Puts your monitors, and the windows on them, back where they belong after wake, unlock and display changes.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            HStack(spacing: 16) {
                Link(destination: AppInfo.repository) { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                Link(destination: AppInfo.issues) { Label("Report an Issue", systemImage: "exclamationmark.bubble") }
            }
            .padding(.top, 16)
            Divider().padding(.vertical, 16)
            Text("© Vladimir Lazarenko")
                .font(.caption)
            Text("MIT License")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .frame(width: 340)
    }
}
