#if TEXTUAL_ENABLE_TEXT_SELECTION
  import SwiftUI

  @testable import Textual

  @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
  extension TextSelectionModel {
    /// A model from a layout recorded in `Fixtures/TextSelectionModel`. The upstream
    /// recorder needed swift-snapshot-testing and is gone; the recorded fixtures stay.
    convenience init(fixtureName name: String) throws {
      let url = Bundle.module.url(
        forResource: "Fixtures/TextSelectionModel/\(name)",
        withExtension: "json"
      )
      let data = try url.map { try Data(contentsOf: $0) } ?? Data()
      let layoutCollection = try JSONDecoder().decode(CodableTextLayoutCollection.self, from: data)

      self.init(layoutCollection: layoutCollection)
    }
  }
#endif
