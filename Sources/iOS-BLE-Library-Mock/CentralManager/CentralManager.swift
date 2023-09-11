//
//  File.swift
//
//
//  Created by Nick Kibysh on 18/04/2023.
//

import Combine
import CoreBluetoothMock
import Foundation

extension CentralManager {
	public enum Err: Error {
		case wrongManager
		case badState(CBManagerState)
		case unknownError

		public var localizedDescription: String {
			switch self {
			case .wrongManager:
				return "Incorrect manager instance provided."
			case .badState(let state):
				return "Bad state: \(state)"
			case .unknownError:
				return "An unknown error occurred."
			}
		}
	}
}

private class Observer: NSObject {
	@objc dynamic private weak var cm: CBCentralManager?
	private weak var publisher: CurrentValueSubject<Bool, Never>?
	private var observation: NSKeyValueObservation?

	init(cm: CBCentralManager, publisher: CurrentValueSubject<Bool, Never>) {
		self.cm = cm
		self.publisher = publisher
		super.init()
	}

	func setup() {
		observation = observe(
			\.cm?.isScanning,
			options: [.old, .new],
			changeHandler: { _, change in

				change.newValue?.flatMap { [weak self] new in
					self?.publisher?.send(new)
				}
			}
		)
	}
}

/// A custom Central Manager class that extends the functionality of the standard CBCentralManager.
/// This class brings a reactive approach and is based on the Swift Combine framework.
public class CentralManager {
	private let isScanningSubject = CurrentValueSubject<Bool, Never>(false)
	private let killSwitchSubject = PassthroughSubject<Void, Never>()
	private lazy var observer = Observer(cm: centralManager, publisher: isScanningSubject)

	public let centralManager: CBCentralManager
	public let centralManagerDelegate: ReactiveCentralManagerDelegate

	/// Initializes a new instance of `CentralManager`.
	/// - Parameters:
	///   - centralManagerDelegate: The delegate for the reactive central manager. Default is `ReactiveCentralManagerDelegate()`.
	///   - queue: The queue to perform operations on. Default is the main queue.
	public init(
		centralManagerDelegate: ReactiveCentralManagerDelegate =
			ReactiveCentralManagerDelegate(), queue: DispatchQueue = .main
	) {
		self.centralManagerDelegate = centralManagerDelegate
		self.centralManager = CBMCentralManagerFactory.instance(
			delegate: centralManagerDelegate, queue: queue)
		observer.setup()
	}

	/// Initializes a new instance of `CentralManager` with an existing CBCentralManager instance.
	/// - Parameter centralManager: An existing CBCentralManager instance.
	/// - Throws: An error if the provided manager's delegate is not of type `ReactiveCentralManagerDelegate`.
	public init(centralManager: CBCentralManager) throws {
		guard
			let reactiveDelegate = centralManager.delegate
				as? ReactiveCentralManagerDelegate
		else {
			throw Err.wrongManager
		}

		self.centralManager = centralManager
		self.centralManagerDelegate = reactiveDelegate

		observer.setup()
	}
}

// MARK: Establishing or Canceling Connections with Peripherals
extension CentralManager {
	/// Establishes a connection with the specified peripheral.
	/// - Parameters:
	///   - peripheral: The peripheral to connect to.
	///   - options: Optional connection options.
	/// - Returns: A publisher that emits the connected peripheral on successful connection.
	///            The publisher does not finish until the peripheral is successfully connected.
	///            If the peripheral was disconnected successfully, the publisher finishes without error.
	///            If the connection was unsuccessful or disconnection returns an error (e.g., peripheral disconnected unexpectedly),
	///            the publisher finishes with an error.
	public func connect(_ peripheral: CBPeripheral, options: [String: Any]? = nil)
		-> Publishers.BluetoothPublisher<CBPeripheral, Error>
	{
		let killSwitch = self.disconnectedPeripheralsChannel.tryFirst(where: { p in
			if let e = p.1 {
				throw e
			}
			return p.0.identifier == peripheral.identifier
		})

		return self.connectedPeripheralChannel
			.filter { $0.0.identifier == peripheral.identifier }
			.tryMap { p in
				if let e = p.1 {
					throw e
				}

				return p.0
			}
			.prefix(untilUntilOutputOrCompletion: killSwitch)
			.bluetooth {
				self.centralManager.connect(peripheral, options: options)
			}
	}

	/// Cancels the connection with the specified peripheral.
	/// - Parameter peripheral: The peripheral to disconnect from.
	/// - Returns: A publisher that emits the disconnected peripheral.
	public func cancelPeripheralConnection(_ peripheral: CBPeripheral) -> Publishers.Peripheral
	{
		return self.disconnectedPeripheralsChannel
			.tryFilter { r in
				guard r.0.identifier == peripheral.identifier else {
					return false
				}

				if let e = r.1 {
					throw e
				} else {
					return true
				}
			}
			.map { $0.0 }
			.first()
			.peripheral {
				self.centralManager.cancelPeripheralConnection(peripheral)
			}
	}
}

// MARK: Retrieving Lists of Peripherals
extension CentralManager {
	/// Returns a list of the peripherals connected to the system whose
	/// services match a given set of criteria.
	///
	/// The list of connected peripherals can include those that other apps
	/// have connected. You need to connect these peripherals locally using
	/// the `connect(_:options:)` method before using them.
	/// - Parameter serviceUUIDs: A list of service UUIDs, represented by
	///                           `CBUUID` objects.
	/// - Returns: A list of the peripherals that are currently connected
	///            to the system and that contain any of the services
	///            specified in the `serviceUUID` parameter.
	public func retrieveConnectedPeripherals(withServices identifiers: [CBUUID])
		-> [CBPeripheral]
	{
		centralManager.retrieveConnectedPeripherals(withServices: identifiers)
	}

	/// Returns a list of known peripherals by their identifiers.
	/// - Parameter identifiers: A list of peripheral identifiers
	///                          (represented by `NSUUID` objects) from which
	///                          ``CBPeripheral`` objects can be retrieved.
	/// - Returns: A list of peripherals that the central manager is able
	///            to match to the provided identifiers.
	public func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] {
		centralManager.retrievePeripherals(withIdentifiers: identifiers)
	}
}

// MARK: Scanning or Stopping Scans of Peripherals
extension CentralManager {
	/// Initiates a scan for peripherals with the specified services.
	/// - Parameter services: The services to scan for.
	/// - Returns: A publisher that emits scan results or errors.
	public func scanForPeripherals(withServices services: [CBUUID]?)
		-> Publishers.BluetoothPublisher<ScanResult, Error>
	{
		stopScan()
		// TODO: Change to BluetoothPublisher
		return centralManagerDelegate.stateSubject
			.tryFirst { state in
				guard let determined = state.ready else { return false }

				guard determined else { throw Err.badState(state) }
				return true
			}
			.flatMap { _ in
				// TODO: Check for mmemory leaks
				return self.centralManagerDelegate.scanResultSubject
					.setFailureType(to: Error.self)
			}
			.map { a in
				return a
			}
			.prefix(untilOutputFrom: killSwitchSubject)
			.mapError { [weak self] e in
				self?.stopScan()
				return e
			}
			.bluetooth {
				self.centralManager.scanForPeripherals(withServices: services)
			}
	}

	/// Stops an ongoing scan for peripherals.
	/// Calling this method finishes the publisher returned by ``scanForPeripherals(withServices:)``.
	public func stopScan() {
		centralManager.stopScan()
		killSwitchSubject.send(())
	}
}

// MARK: Channels
extension CentralManager {
	/// A publisher that emits the state of the central manager.
	public var stateChannel: AnyPublisher<CBManagerState, Never> {
		centralManagerDelegate
			.stateSubject
			.eraseToAnyPublisher()
	}

	/// A publisher that emits the scanning state.
	public var isScanningChannel: AnyPublisher<Bool, Never> {
		isScanningSubject
			.eraseToAnyPublisher()
	}

	/// A publisher that emits scan results.
	public var scanResultsChannel: AnyPublisher<ScanResult, Never> {
		centralManagerDelegate.scanResultSubject
			.eraseToAnyPublisher()
	}

	/// A publisher that emits connected peripherals along with errors.
	public var connectedPeripheralChannel: AnyPublisher<(CBPeripheral, Error?), Never> {
		centralManagerDelegate.connectedPeripheralSubject
			.eraseToAnyPublisher()
	}

	/// A publisher that emits disconnected peripherals along with errors.
	public var disconnectedPeripheralsChannel: AnyPublisher<(CBPeripheral, Error?), Never> {
		centralManagerDelegate.disconnectedPeripheralsSubject
			.eraseToAnyPublisher()
	}
}