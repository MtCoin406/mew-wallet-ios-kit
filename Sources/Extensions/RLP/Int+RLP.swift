//
//  Int+RLP.swift
//  MEWwalletKit
//
//  Created by Mikhail Nikanorov on 4/25/19.
//  Copyright © 2019 MyEtherWallet Inc. All rights reserved.
//

import Foundation

extension Int: RLP, RLPLength {
  func rlpEncode(offset: UInt8?) -> Data? {
    guard let offset = offset else {
      return MEWBigInt<UInt8>(self).reversedData.rlpEncode()
    }
    return self.rlpLengthEncode(offset: offset)
  }
  
  func rlpLengthEncode(offset: UInt8) -> Data? {
    guard self >= 0 else {
      return nil
    }
    if self < 56 {
      return Data([UInt8(self) + offset])
    } else {
      return MEWBigInt<UInt8>(self).rlpLengthEncode(offset: offset)
    }
  }
}
