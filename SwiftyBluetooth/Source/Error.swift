//
//  SBError.swift
//
//  Copyright (c) 2016 Jordane Belanger
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import CoreBluetooth

public enum SBError: Error {
    case bluetoothUnsupported
    case bluetoothUnauthorized
    case bluetoothPoweredOff
    case operationTimeoutError(operationName: String)
    case coreBluetoothError(operationName: String, error: Error)
    case invalidPeripheral
    case peripheralFailedToConnectReasonUnknown
    case peripheralServiceNotFound(missingServicesUUIDs: [CBUUID])
    case peripheralCharacteristicNotFound(missingCharacteristicsUUIDs: [CBUUID])
    case peripheralDescriptorsNotFound(missingDescriptorsUUIDs: [CBUUID])
    case scanTerminatedUnexpectedly(invalidState: Int) // CBCentralManagerState.rawValue (CBManagerState.rawValue for iOS 10)
    case invalidDescriptorValue(descriptor: CBDescriptor)
    
    public var _domain: String {
        get {
            return "com.swiftybluetooth.error"
        }
    }
    
    public var _code: Int {
        get {
            switch self {
            case .operationTimeoutError:
                return 100
            case .coreBluetoothError:
                return 101
            case .peripheralServiceNotFound:
                return 102
            case .peripheralCharacteristicNotFound:
                return 103
            case .peripheralDescriptorsNotFound:
                return 104
            case .bluetoothUnsupported:
                return 105
            case .bluetoothUnauthorized:
                return 106
            case .bluetoothPoweredOff:
                return 107
            case .invalidPeripheral:
                return 108
            case .peripheralFailedToConnectReasonUnknown:
                return 109
            case .scanTerminatedUnexpectedly:
                return 110
            case .invalidDescriptorValue:
                return 111
            }
        }
    }
    
    public func NSErrorRepresentation() -> NSError {
        switch self {
        case .operationTimeoutError(let operationName):
            return self.errorWithDescription("SwiftyBluetooth timeout error", failureReason: "Timed out during \"\(operationName)\" operation.")
        
        case .coreBluetoothError(let operationName, let cbError):
            return self.errorWithDescription("CoreBluetooth Error during \(operationName).", failureReason: cbError.localizedDescription)
        
        case .peripheralServiceNotFound(let missingServices):
            let missingServicesString = missingServices.map { $0.uuidString }.joined(separator: ",")
            return self.errorWithDescription("Peripheral Error", failureReason: "Failed to find the service by your operation: \(missingServicesString)")
        
        case .peripheralCharacteristicNotFound(let missingCharacs):
            let missingCharacsString = missingCharacs.map { $0.uuidString }.joined(separator: ",")
            return self.errorWithDescription("Peripheral Error", failureReason: "Failed to find the characteristics by your operation: \(missingCharacsString)")
        
        case .peripheralDescriptorsNotFound(let missingDescriptors):
            let missingDescriptorsString = missingDescriptors.map { $0.uuidString }.joined(separator: ",")
            return self.errorWithDescription("Peripheral Error", failureReason: "Failed to find the descriptor by your operation: \(missingDescriptorsString)")
        
        case .bluetoothUnsupported:
            return self.errorWithDescription("Bluetooth unsupported.", failureReason: "Your iOS Device must support Bluetooth to use SwiftyBluetooth.")
        
        case .bluetoothUnauthorized:
            return self.errorWithDescription("Bluetooth unauthorized", failureReason: "Bluetooth must be authorized for your operation to complete.")
        
        case .bluetoothPoweredOff:
            return self.errorWithDescription("Bluetooth powered off", failureReason: "Bluetooth needs to be powered on for your operation to complete.", recoverySuggestion: "Turn on bluetooth in your iOS device's settings.")
        
        case .invalidPeripheral:
            return self.errorWithDescription("Invalid peripheral", failureReason: "Bluetooth became unreachable while using this Peripheral, the Peripheral must be discovered again to be used.", recoverySuggestion: "Rediscover the Peripheral.")
        
        case .peripheralFailedToConnectReasonUnknown:
            return self.errorWithDescription("Failed to connect your Peripheral", failureReason: "Unknown reason")
            
        case .scanTerminatedUnexpectedly:
            return self.errorWithDescription("Scan terminated unexpectedly", failureReason: "You're iOS device bluetooth was desactivated", recoverySuggestion: "Restart bluetooth and try scanning again")
            
        case .invalidDescriptorValue(let descriptor):
            return self.errorWithDescription("Invalid descriptor value", failureReason: "Unparsable value for descriptor: \(descriptor.description)")
        }
    }
    
    fileprivate func errorWithDescription(_ description: String, failureReason: String? = nil, recoverySuggestion: String? = nil) -> NSError {
        var userInfo: [AnyHashable: Any] = [NSLocalizedDescriptionKey: description]
        if let failureReason = failureReason {
            userInfo[NSLocalizedFailureReasonErrorKey] = failureReason
        }
        if let recoverySuggestion = recoverySuggestion {
            userInfo[NSLocalizedRecoverySuggestionErrorKey] = recoverySuggestion
        }
        
        return NSError(domain: self._domain, code: self._code, userInfo: userInfo)
    }
}
