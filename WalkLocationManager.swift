import Foundation
import CoreLocation
import SwiftUI

/// Natywne śledzenie spaceru przez CoreLocation.
/// Do działania w tle wymagany jest Background Mode: Location oraz zgoda lokalizacyjna użytkownika.
@MainActor
final class WalkLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isTracking = false
    @Published private(set) var statusMessage = "Lokalizacja wyłączona"
    @Published private(set) var lastSentAt: Date?

    private let manager = CLLocationManager()
    private var bookingID: String?
    private var lastUploadAt = Date.distantPast

    private let savedBookingKey = "naspacerze.activeWalkBookingID"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        // Właściwość włączamy dopiero przy aktywnym spacerze.
    }

    func start(bookingID: String) {
        self.bookingID = bookingID
        UserDefaults.standard.set(bookingID, forKey: savedBookingKey)

        guard CLLocationManager.locationServicesEnabled() else {
            statusMessage = "Włącz Usługi lokalizacji w Ustawieniach iPhone’a."
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            statusMessage = "Oczekiwanie na zgodę na lokalizację…"
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            beginUpdates()
            // Użytkownik może później rozszerzyć zgodę do „Zawsze” w Ustawieniach.
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            beginUpdates()
        case .denied, .restricted:
            statusMessage = "Brak zgody na lokalizację. Zmień ją w Ustawieniach iPhone’a."
        @unknown default:
            statusMessage = "Nieznany status uprawnień lokalizacyjnych."
        }
    }

    func resumeSavedWalkIfNeeded() {
        guard let saved = UserDefaults.standard.string(forKey: savedBookingKey) else { return }
        bookingID = saved
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            beginUpdates()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        bookingID = nil
        isTracking = false
        statusMessage = "Lokalizacja wyłączona"
        UserDefaults.standard.removeObject(forKey: savedBookingKey)
    }

    private func beginUpdates() {
        guard bookingID != nil else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isTracking = true
        statusMessage = "Udostępnianie lokalizacji aktywne"
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard bookingID != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdates()
        case .denied, .restricted:
            statusMessage = "Brak zgody na lokalizację."
            isTracking = false
        case .notDetermined:
            break
        @unknown default:
            statusMessage = "Nieznany status lokalizacji."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 100,
              let bookingID,
              Date().timeIntervalSince(lastUploadAt) >= 5 else { return }

        lastUploadAt = Date()
        let payload: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy
        ]

        Task {
            do {
                _ = try await APIClient.shared.request("POST", "walks/\(bookingID)/location", body: payload)
                lastSentAt = Date()
                statusMessage = "Ostatnia pozycja wysłana: \(Date.now.formatted(date: .omitted, time: .shortened))"
            } catch {
                // Przy chwilowym braku sieci GPS nadal działa; kolejny punkt spróbuje ponownie.
                statusMessage = "GPS aktywny — oczekiwanie na połączenie z serwerem."
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusMessage = "Błąd lokalizacji: \(error.localizedDescription)"
    }
}
