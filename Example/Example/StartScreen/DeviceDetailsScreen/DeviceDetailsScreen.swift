//
//  DeviceDetailsScreen.swift
//  Example
//
//  Created by Nick Kibysh on 29/03/2023.
//

import SwiftUI
import iOS_Common_Libraries

struct DeviceDetailsScreen: View {
    @ObservedObject var viewModel: ViewModel
    
    var body: some View {
        Form {
            Section("Device") {
                HeaderView(
                    name: viewModel.name,
                    rssi: viewModel.rssi,
                    connectable: viewModel.isConnectable,
                    state: viewModel.connectionState
                )
            }
            
            Section("Advertisement Data") {
                AdvertisementDataView(advData: viewModel.advertisementData)
            }
            
            Section {
                connectionButton(state: viewModel.connectionState)
            } footer: {
                if !viewModel.isConnectable {
                    Text("The device is not connectable")
                }
            }
        }
        .navigationTitle("Device")
    }
    
    @ViewBuilder
    func connectionButton(state: CBPeripheralState) -> some View {
        if state == .disconnected || state == .connecting {
            Button("CONNECT") {
                Task {
                    await viewModel.connect()
                }
            }
            .disabled(state == .connecting)
            .buttonStyle(NordicPrimary())
        } else {
            Button("DISCONNECT") {
                
            }
            .buttonStyle(NordicPrimaryDistructive())
            .disabled(state == .disconnecting)
        }
    }
}

struct DeviceDetailsScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DeviceDetailsScreen(
                viewModel: DeviceDetailsScreen.PreviewViewModel(
                    name: "Device",
                    connectable: false
                )
            )
        }
    }
}

