//
//  ScannerViewModel+State.swift
//  nRF-BLES-Example
//
//  Created by Nick Kibysh on 14/06/2023.
//

import Foundation

extension ScannerViewModel {
    enum BluetoothState: String {
        case unknown = "Bluetooth State is unknownn"
        case resetting = "Resetting..."
        case unsupported = "Bluetooth is unsupported on this device"
        case unauthorized = "Bluetooth is unauthorized. Open system settings and grant permissions to use all features of the app"
        case poweredOff = "Bluetooth is powered OFF"
        case poweredOn = "Powered ON"
        
        init(cbmState: CBManagerState) {
            switch cbmState {
            case .unknown:
                self = .unknown
            case .resetting:
                self = .resetting
            case .unsupported:
                self = .unsupported
            case .unauthorized:
                self = .unauthorized
            case .poweredOff:
                self = .poweredOff
            case .poweredOn:
                self = .poweredOn
            }
        }
        
        init(cbState: CBManagerState) {
            switch cbState {
            case .unknown:
                self = .unknown
            case .resetting:
                self = .resetting
            case .unsupported:
                self = .unsupported
            case .unauthorized:
                self = .unauthorized
            case .poweredOff:
                self = .poweredOff
            case .poweredOn:
                self = .poweredOn
            }
        }
    }
}
