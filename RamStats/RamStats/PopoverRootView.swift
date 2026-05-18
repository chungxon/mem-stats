import SwiftUI

struct PopoverRootView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Ram Stats")
          .font(.headline)
        Spacer()
      }

      Divider()

      Text("Task 1 shell is ready.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Spacer()
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}
