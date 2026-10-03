import Foundation

struct DonutSlice: Identifiable, Equatable {
  enum Category: Equatable {
    case user(String)
    case others
    case unattributed
    case free
  }

  let id: String
  let label: String
  let category: Category
  let bytes: UInt64
  let fractionOfTotal: Double

  var angleValue: Double {
    Double(bytes)
  }
}
