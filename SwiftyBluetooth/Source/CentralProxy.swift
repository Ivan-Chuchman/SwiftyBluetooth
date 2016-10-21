//
//  CentralProxy.swift
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

final class CentralProxy: NSObject {
    fileprivate lazy var asyncCentralStateCallbacks: [AsyncCentralStateCallback] = []
    
    fileprivate var scanRequest: PeripheralScanRequest?
    
    fileprivate lazy var connectRequests: [UUID: ConnectPeripheralRequest] = [:]
    fileprivate lazy var disconnectRequests: [UUID: DisconnectPeripheralRequest] = [:]
    
    let centralManager: CBCentralManager
    
    override init() {
        self.centralManager = CBCentralManager(delegate: nil, queue: nil)
        super.init()
        self.centralManager.delegate = self
    }
    
    fileprivate func postCentralEvent(_ event: CentralEvent, userInfo: [AnyHashable: Any]? = nil) {
        NotificationCenter.default.post(
            name: Notification.Name(rawValue: event.rawValue),
            object: Central.sharedInstance,
            userInfo: userInfo)
    }
}

// MARK: Initialize Bluetooth requests
extension CentralProxy {
    func asyncCentralState(_ completion: @escaping AsyncCentralStateCallback) {
        switch centralManager.state {
        case .unknown:
            self.asyncCentralStateCallbacks.append(completion)
        case .resetting:
            self.asyncCentralStateCallbacks.append(completion)
        case .unsupported:
            completion(.unsupported)
        case .unauthorized:
            completion(.unauthorized)
        case .poweredOff:
            completion(.poweredOff)
        case .poweredOn:
            completion(.poweredOn)
        }
    }
    
    func initializeBluetooth(_ completion: @escaping InitializeBluetoothCallback) {
        self.asyncCentralState { (state) in
            switch state {
            case .unsupported:
                completion(.bluetoothUnsupported)
            case .unauthorized:
                completion(.bluetoothUnauthorized)
            case .poweredOff:
                completion(.bluetoothPoweredOff)
            case .poweredOn:
                completion(nil)
            }
        }
    }
    
    func callAsyncCentralStateCallback(_ state: AsyncCentralState) {
        let callbacks = self.asyncCentralStateCallbacks
        
        self.asyncCentralStateCallbacks.removeAll()
        
        for callback in callbacks {
            callback(state)
        }
    }
}

// MARK: Scan requests
private final class PeripheralScanRequest {
    let callback: PeripheralScanCallback
    
    init(callback: @escaping PeripheralScanCallback) {
        self.callback = callback
    }
}

extension CentralProxy {
    func scanWithTimeout(_ timeout: TimeInterval, serviceUUIDs: [CBUUID]?, _ callback: @escaping PeripheralScanCallback) {
        initializeBluetooth { [unowned self] (error) in
            if let error = error {
                callback(PeripheralScanResult.scanStopped(error: error))
            } else {
                if self.scanRequest != nil {
                    self.centralManager.stopScan()
                }
                
                let scanRequest = PeripheralScanRequest(callback: callback)
                self.scanRequest = scanRequest
                
                scanRequest.callback(.scanStarted)
                self.centralManager.scanForPeripherals(withServices: serviceUUIDs, options: nil)
                
                Timer.scheduledTimer(
                    timeInterval: timeout,
                    target: self,
                    selector: #selector(self.onScanTimerTick),
                    userInfo: Weak(value: scanRequest),
                    repeats: false)
            }
        }
    }
    
    func stopScan(_ error: SBError? = nil) {
        self.centralManager.stopScan()
        if let scanRequest = self.scanRequest {
            self.scanRequest = nil
            scanRequest.callback(.scanStopped(error: error))
        }
    }
    
    @objc fileprivate func onScanTimerTick(_ timer: Timer) {
        
        defer {
            if timer.isValid { timer.invalidate() }
        }
        
        let weakRequest = timer.userInfo as! Weak<PeripheralScanRequest>
        
        if weakRequest.value != nil {
            self.stopScan()
        }
    }
}

// MARK: Connect Peripheral requests
private final class ConnectPeripheralRequest {
    var callbacks: [PeripheralConnectCallback] = []
    
    let peripheral: CBPeripheral
    
    init(peripheral: CBPeripheral, callback: @escaping PeripheralConnectCallback) {
        self.callbacks.append(callback)
        
        self.peripheral = peripheral
    }
    
    func invokeCallbacks(_ error: SBError?) {
        for callback in callbacks {
            callback(error)
        }
    }
}

extension CentralProxy {
    func connectPeripheral(_ peripheral: CBPeripheral, timeout: TimeInterval, _ callback: @escaping (_ error: SBError?) -> Void) {
        initializeBluetooth { [unowned self] (error) in
            if let error = error {
                callback(error)
                return
            }
            
            let uuid = peripheral.identifier
            
            if let cbPeripheral = self.centralManager.retrievePeripherals(withIdentifiers: [uuid]).first , cbPeripheral.state == .connected {
                callback(nil)
                return
            }
            
            if let request = self.connectRequests[uuid] {
                request.callbacks.append(callback)
            } else {
                let request = ConnectPeripheralRequest(peripheral: peripheral, callback: callback)
                self.connectRequests[uuid] = request
                
                self.centralManager.connect(peripheral, options: nil)
                Timer.scheduledTimer(
                    timeInterval: timeout,
                    target: self,
                    selector: #selector(self.onConnectTimerTick),
                    userInfo: Weak(value: request),
                    repeats: false)
            }
        }
    }
    
    @objc fileprivate func onConnectTimerTick(_ timer: Timer) {
        defer {
            if timer.isValid { timer.invalidate() }
        }
        
        let weakRequest = timer.userInfo as! Weak<ConnectPeripheralRequest>
        guard let request = weakRequest.value else {
            return
        }
        
        let uuid = request.peripheral.identifier
        
        self.connectRequests[uuid] = nil
        
        request.invokeCallbacks(SBError.operationTimeoutError(operationName: "connect peripheral"))
    }
}

// MARK: Disconnect Peripheral requests
private final class DisconnectPeripheralRequest {
    var callbacks: [PeripheralConnectCallback] = []
    
    let peripheral: CBPeripheral
    
    init(peripheral: CBPeripheral, callback: @escaping PeripheralDisconnectCallback) {
        self.callbacks.append(callback)
        
        self.peripheral = peripheral
    }
    
    func invokeCallbacks(_ error: SBError?) {
        for callback in callbacks {
            callback(error)
        }
    }
}

extension CentralProxy {
    func disconnectPeripheral(_ peripheral: CBPeripheral, timeout: TimeInterval, _ callback: @escaping (_ error: SBError?) -> Void) {
        initializeBluetooth { [unowned self] (error) in
            
            if let error = error {
                callback(error)
                return
            }
            
            let uuid = peripheral.identifier
            
            if let cbPeripheral = self.centralManager.retrievePeripherals(withIdentifiers: [uuid]).first
                , (cbPeripheral.state == .disconnected || cbPeripheral.state == .disconnecting) {
                callback(nil)
                return
            }
            
            if let request = self.disconnectRequests[uuid] {
                request.callbacks.append(callback)
            } else {
                let request = DisconnectPeripheralRequest(peripheral: peripheral, callback: callback)
                self.disconnectRequests[uuid] = request
                
                self.centralManager.cancelPeripheralConnection(peripheral)
                Timer.scheduledTimer(
                    timeInterval: timeout,
                    target: self,
                    selector: #selector(self.onDisconnectTimerTick),
                    userInfo: Weak(value: request),
                    repeats: false)
            }
        }
    }
    
    @objc fileprivate func onDisconnectTimerTick(_ timer: Timer) {
        defer {
            if timer.isValid { timer.invalidate() }
        }
        
        let weakRequest = timer.userInfo as! Weak<DisconnectPeripheralRequest>
        guard let request = weakRequest.value else {
            return
        }
        
        let uuid = request.peripheral.identifier
        
        self.disconnectRequests[uuid] = nil
        
        request.invokeCallbacks(SBError.operationTimeoutError(operationName: "disconnect peripheral"))
    }
}

extension CentralProxy: CBCentralManagerDelegate {
    @objc func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.postCentralEvent(.CentralStateChange, userInfo: ["state": Box(value: central.state.rawValue)])
        switch centralManager.state.rawValue {
            case 0: //.Unknown:
                self.stopScan(SBError.scanTerminatedUnexpectedly(invalidState: centralManager.state.rawValue))
            case 1: //.Resetting:
                self.stopScan(SBError.scanTerminatedUnexpectedly(invalidState: centralManager.state.rawValue))
            case 2: //.Unsupported:
                self.callAsyncCentralStateCallback(.unsupported)
                self.stopScan(SBError.scanTerminatedUnexpectedly(invalidState: centralManager.state.rawValue))
            case 3: //.Unauthorized:
                self.callAsyncCentralStateCallback(.unauthorized)
                self.stopScan(SBError.scanTerminatedUnexpectedly(invalidState: centralManager.state.rawValue))
            case 4: //.PoweredOff:
                self.callAsyncCentralStateCallback(.poweredOff)
                self.stopScan(SBError.scanTerminatedUnexpectedly(invalidState: centralManager.state.rawValue))
            case 5: //.PoweredOn:
                self.callAsyncCentralStateCallback(.poweredOn)
            default:
                break
        }
    }
    
    @objc func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let uuid = peripheral.identifier
        guard let request = self.connectRequests[uuid] else {
            return
        }
        
        self.connectRequests[uuid] = nil
        
        request.invokeCallbacks(nil)
    }
    
    @objc func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let uuid = peripheral.identifier
        guard let request = self.disconnectRequests[uuid] else {
            return
        }
        
        self.disconnectRequests[uuid] = nil
        
        var swiftyError: SBError?
        if let error = error {
            swiftyError = SBError.coreBluetoothError(operationName: "disconnect peripheral", error: error)
        }
        
        request.invokeCallbacks(swiftyError)
    }
    
    @objc func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let uuid = peripheral.identifier
        guard let request = self.connectRequests[uuid] else {
            return
        }
        
        var swiftyError: SBError?
        if let error = error {
            swiftyError = .coreBluetoothError(operationName: "connect peripheral", error: error)
        } else {
            swiftyError = SBError.peripheralFailedToConnectReasonUnknown
        }
        
        self.connectRequests[uuid] = nil
        
        request.invokeCallbacks(swiftyError)
    }
    
    @objc func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        guard let scanRequest = scanRequest else {
            return
        }
        
        let peripheral = Peripheral(peripheral: peripheral)
        
        scanRequest.callback(.scanResult(peripheral: peripheral, advertisementData: advertisementData as [String : AnyObject], RSSI: RSSI))
    }
    
    @objc func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        self.postCentralEvent(.CentralManagerWillRestoreState, userInfo: dict)
    }
}
