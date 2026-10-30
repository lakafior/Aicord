//
//  ToolAgent.swift
//  AicordKit
//
//  A model that answers by calling read-only functions (search, nearby
//  messages, reply chains) until it knows enough, within a fixed budget.
//

import Foundation

/// A JSON value, for function schemas and arguments.
public enum JSONValue: Codable, Sendable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case array([JSONValue])
  case object([String: JSONValue])
  case null

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  /// An object schema with optional properties: `[name: (type, description)]`.
  public static func objectSchema(
    _ properties: [(name: String, type: String, description: String)], required: [String] = []
  ) -> JSONValue {
    var props: [String: JSONValue] = [:]
    for property in properties {
      props[property.name] = .object([
        "type": .string(property.type), "description": .string(property.description),
      ])
    }
    return .object([
      "type": .string("object"),
      "properties": .object(props),
      "required": .array(required.map(JSONValue.string)),
    ])
  }
}

public struct ToolAgent: Sendable {
  public struct Tool: Sendable {
    public var definition: OpenAICompatibleClient.ToolDefinition
    /// Runs the call with the model's JSON arguments and returns text for it.
    public var run: @Sendable (_ arguments: String) async throws -> String

    public init(
      name: String, description: String, parameters: JSONValue,
      run: @escaping @Sendable (_ arguments: String) async throws -> String
    ) {
      definition = .init(name: name, description: description, parameters: parameters)
      self.run = run
    }
  }

  /// One model turn: the conversation so far in, a reply or calls out.
  public typealias Turn = @Sendable (
    _ messages: [OpenAICompatibleClient.Message], _ tools: [OpenAICompatibleClient.ToolDefinition]
  ) async throws -> OpenAICompatibleClient.Message

  public var tools: [Tool]
  /// Calls allowed per question; Discord's search is strictly rate limited.
  public var maxCalls: Int
  public var turn: Turn

  public init(tools: [Tool], maxCalls: Int, turn: @escaping Turn) {
    self.tools = tools
    self.maxCalls = maxCalls
    self.turn = turn
  }

  public static let limitReached =
    "No more lookups are allowed. Answer now with what you have, or say what you couldn't find."

  /// The model's final answer. Once the budget is spent the tools are taken
  /// away, so the next turn has to answer.
  public func answer(instructions: String, prompt: String) async throws -> String {
    var messages: [OpenAICompatibleClient.Message] = [.system(instructions), .user(prompt)]
    var calls = 0
    for _ in 0..<(maxCalls + 3) {
      try Task.checkCancellation()
      let offered = calls < maxCalls ? tools.map(\.definition) : []
      let reply = try await turn(messages, offered)
      guard let requested = reply.tool_calls, !requested.isEmpty else {
        return reply.content.text
      }
      messages.append(reply)
      for call in requested {
        try Task.checkCancellation()
        let result: String
        if calls >= maxCalls {
          result = Self.limitReached
        } else if let tool = tools.first(where: { $0.definition.function.name == call.function.name }) {
          calls += 1
          do {
            result = try await tool.run(call.function.arguments)
          } catch is CancellationError {
            throw CancellationError()
          } catch {
            result = "The lookup failed: \(error.localizedDescription)"
          }
        } else {
          result = "There is no function called \(call.function.name)."
        }
        messages.append(.tool(result, callID: call.id))
      }
    }
    throw OpenAICompatibleClient.ClientError.emptyReply
  }
}
