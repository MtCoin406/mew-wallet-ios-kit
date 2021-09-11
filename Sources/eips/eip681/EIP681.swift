//
//  EIP681.swift
//  MEWwalletKit
//
//  Created by Mikhail Nikanorov on 9/10/21.
//  Copyright © 2019 MyEtherWallet Inc. All rights reserved.
//

import Foundation
import BigInt

public struct EIP681Code {
  public enum CodeType: String {
    case pay
  }
  public struct Parameter: Equatable {
    public var type: ABI.Element.ParameterType
    public var value: AnyObject
    
    public static func == (lhs: EIP681Code.Parameter, rhs: EIP681Code.Parameter) -> Bool {
      switch (lhs.value, rhs.value) {
      case let (lhsValue as Address, rhsValue as Address): return lhsValue == rhsValue && lhs.type == rhs.type
      case let (lhsValue as BigInt, rhsValue as BigInt): return lhsValue == rhsValue && lhs.type == rhs.type
      case let (lhsValue as BigUInt, rhsValue as BigUInt): return lhsValue == rhsValue && lhs.type == rhs.type
      case let (lhsValue as String, rhsValue as String): return lhsValue == rhsValue && lhs.type == rhs.type
      case let (lhsValue as Data, rhsValue as Data): return lhsValue == rhsValue && lhs.type == rhs.type
      case let (lhsValue as Bool, rhsValue as Bool): return lhsValue == rhsValue && lhs.type == rhs.type
      default: return false
      }
    }
  }
  
  // MARK: - Properties
  
  public var targetAddress: Address
  public var receipientAddress: Address? {
    guard self.function == nil else { return nil }
    return self.parameters.first(where: { $0.type == .address })?.value as? Address
  }
  public var chainID: BigInt?
  public var type: CodeType = .pay
  public var functionName: String?
  public var parameters: [Parameter] = []
  public var gasLimit: BigInt?
  public var value: BigInt?
  public var function: ABI.Element.Function?
  
  public init(_ targetAddress: Address) {
    self.targetAddress = targetAddress
  }
  
  public init?(_ data: Data) {
    guard let val = EIP681CodeParser.parse(data) else { return nil }
    self = val
  }
  
  public init?(_ string: String) {
    guard let val = EIP681CodeParser.parse(string) else { return nil }
    self = val
  }
}

// MARK: - Parser

private struct EIP681CodeParser {
  static func parse(_ data: Data) -> EIP681Code? {
    guard let string = String(data: data, encoding: .utf8) else { return nil }
    return parse(string)
  }
  
  static func parse(_ string: String) -> EIP681Code? {
    guard let encoding = string.removingPercentEncoding,
          let matcher: NSRegularExpression = .eip681 else { return nil }
    
    let matches = matcher.matches(in: encoding, options: .anchored, range: encoding.fullNSRange)
    
    guard matches.count == 1,
          let match = matches.first else { return nil }
    
    guard let target = match.eip681Target(in: encoding),
          let targetAddress = Address(ethereumAddress: target) else { return nil }
    
    var code = EIP681Code(targetAddress)
    
    if let type = match.eip681Type(in: encoding) {
      code.type = EIP681Code.CodeType(rawValue: type.lowercased()) ?? .pay
    }
    
    if let chainId = match.eip681ChainID(in: encoding) {
      code.chainID = BigInt(chainId)
    }
    
    code.functionName = match.eip681FunctionName(in: encoding)
    
    var inputs: [ABI.Element.InOut] = []
    
    guard var parameters = match.eip681Parameters(in: encoding) else {
      code.function = _buildFunction(code: code, inputs: inputs)
      return code
    }
    parameters = "?" + parameters
    guard let components = URLComponents(string: parameters) else {
      code.function = _buildFunction(code: code, inputs: inputs)
      return code
    }
    
    guard let queryItems = components.queryItems else {
      code.function = _buildFunction(code: code, inputs: inputs)
      return code
    }
    var inputNumber: Int = 0
    
    for comp in queryItems {
      if let inputType = try? ABITypeParser.parseTypeString(comp.name) {
        guard let value = comp.value else { continue }
        var nativeValue: AnyObject? = nil
        
        switch inputType {
        case .address:
          if let val = Address(ethereumAddress: value) {
            nativeValue = val as AnyObject
          }
          
        case .uint(bits: _):
          if value.isHexWithPrefix(), let val = BigUInt(value.stringRemoveHexPrefix(), radix: 16) {
            nativeValue = val as AnyObject
          } else if let val = BigUInt(scienceNotation: value) {
            nativeValue = val as AnyObject
          }
        case .int(bits: _):
          if value.isHexWithPrefix(), let val = BigInt(value.stringRemoveHexPrefix(), radix: 16) {
            nativeValue = val as AnyObject
          } else if let val = BigInt(scienceNotation: value) {
            nativeValue = val as AnyObject
          }
          
        case .string:
          nativeValue = value as AnyObject
          
        case .dynamicBytes:
          if value.isHex() {
            let val = Data(hex: value)
            nativeValue = val as AnyObject
          } else if let val = value.data(using: .utf8) {
            nativeValue = val as AnyObject
          }
          
        case .bytes(length: _):
          if value.isHex() {
            let val = Data(hex: value)
            nativeValue = val as AnyObject
          } else if let val = value.data(using: .utf8) {
            nativeValue = val as AnyObject
          }
          
        case .bool:
          switch value.lowercased() {
          case "true", "1":
            nativeValue = true as AnyObject
          case "false", "0":
            nativeValue = false as AnyObject
          default:
            nativeValue = true as AnyObject
          }
          
        case .function, .array, .tuple: // Not supported
          continue
        }
        guard let nativeValue = nativeValue else { return nil }
        
        inputs.append(.init(name: String(inputNumber), type: inputType))
        code.parameters.append(.init(type: inputType, value: nativeValue))
        inputNumber += 1
      } else {
        switch comp.name {
        case "value":
          guard let value = comp.value,
                let val = BigInt(scienceNotation: value) else { return nil }
          code.value = val

        case "gas", "gasLimit":
          guard let value = comp.value,
                let val = BigInt(scienceNotation: value) else { return nil }
          code.gasLimit = val
          
        case "gasPrice":
          break
        default:
          continue
        }
      }
    }
    
    code.function = _buildFunction(code: code, inputs: inputs)
    return code
  }
  
  private static func _buildFunction(code: EIP681Code, inputs: [ABI.Element.InOut]) -> ABI.Element.Function? {
    guard let functionName = code.functionName else { return nil }
    return ABI.Element.Function(name: functionName,
                                inputs: inputs,
                                outputs: [],
                                constant: false,
                                payable: code.value != nil)
  }
}
