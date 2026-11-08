import SwiftUI

extension View {
    /// A grouped form whose first card sits right under the toolbar, as in System Settings on macOS 26.
    /// The form's built-in 20-point top margin can't be changed, so the form itself moves up by that much.
    @ViewBuilder
    func paneFormStyle() -> some View {
        if #available(macOS 26, *) {
            formStyle(.grouped)
                .padding(.top, -20)
        } else {
            formStyle(.grouped)
        }
    }
}
