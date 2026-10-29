import Foundation
import Logging
import libzstd

private let minimumAllocation = 4096

enum DecompressionError: Error {
  case initializationFailed
  case incompleteFrame
  case unknownFailure(resultCode: Int)
  case decompressionError(description: String)
}

final class ZstdStreamingDecompressor: @unchecked Sendable {
  private let dctx: OpaquePointer

  init() throws {
    guard let dctx = ZSTD_createDCtx() else {
      throw DecompressionError.initializationFailed
    }
    self.dctx = dctx
  }

  deinit {
    ZSTD_freeDCtx(dctx)
  }

  func decompress(data: Data) throws -> Data {
    guard !data.isEmpty else { return Data() }

    let chunkSize = max(minimumAllocation, data.count * 8)
    var outData = Data()
    outData.reserveCapacity(chunkSize)
    var chunkBuffer = [UInt8](repeating: 0, count: chunkSize)

    try data.withUnsafeBytes { srcBytes in
      var input = ZSTD_inBuffer(
        src: srcBytes.baseAddress,
        size: srcBytes.count,
        pos: 0
      )

      while true {
        try chunkBuffer.withUnsafeMutableBytes { dstBytes in
          var output = ZSTD_outBuffer(
            dst: dstBytes.baseAddress,
            size: dstBytes.count,
            pos: 0
          )

          let resultCode = ZSTD_decompressStream(dctx, &output, &input)
          if ZSTD_isError(resultCode) != 0 {
            let errorName = ZSTD_getErrorName(resultCode).map {
              String(cString: $0)
            }
            let description =
              errorName ?? "Failed with error result '\(resultCode)'"
            throw DecompressionError.decompressionError(description: description)
          }

          if output.pos > 0, let base = dstBytes.baseAddress {
            outData.append(base.assumingMemoryBound(to: UInt8.self), count: output.pos)
          }
        }

        if input.pos >= input.size {
          break
        }
      }
    }

    return outData
  }
}
