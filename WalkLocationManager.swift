import Foundation
import CoreLocation
import SwiftUI

@MainActor
final class WalkLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isTracking = false
    @Published private(set) var statusMessage = "Lokalizacja wyłączona"
    @Published private(set) var lastSentAt: Date?
    private let manager = CLLocationManager()
    private var bookingID: String?
    private var sending = false
    private var heartbeat: Task<Void, Never>?
    private let savedBookingKey = "naspacerze.activeWalkBookingID"
    private let queueKey = "naspacerze.gpsQueue.v2"
    private struct Point: Codable {
        let latitude: Double
        let longitude: Double
        let accuracy: Double
        let timestamp: String
        let client_point_id: String
    }
    private var queue: [Point] = []
    private var logoutObserver: NSObjectProtocol?

    override init() {
        super.init()
        logoutObserver = NotificationCenter.default.addObserver(forName: Notification.Name("NaSpacerze.logout"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        if let data = UserDefaults.standard.data(forKey: queueKey) {
            queue = (try? JSONDecoder().decode([Point].self, from: data)) ?? []
            let cutoff = Date().addingTimeInterval(-30 * 86400)
            queue.removeAll { (ISO8601DateFormatter().date(from: $0.timestamp) ?? .distantPast) < cutoff }
        }
    }
    deinit { if let logoutObserver { NotificationCenter.default.removeObserver(logoutObserver) } }
    func start(bookingID: String) {
        if let current = self.bookingID, current != bookingID { stop() }
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
        case .authorizedWhenInUse, .authorizedAlways: beginUpdates()
        default: statusMessage = "Zezwól na dokładną lokalizację w Ustawieniach iPhone’a."
        }
    }
    func resumeSavedWalkIfNeeded() {
        guard let id = UserDefaults.standard.string(forKey: savedBookingKey) else { return }
        Task {
            do {
                let data = try await APIClient.shared.request("GET", "walks/\(id)")
                let booking = data["booking"] as? [String: Any] ?? [:]
                let walk = data["walk"] as? [String: Any] ?? [:]
                let me = try await APIClient.shared.request("GET", "auth/me")["user"] as? [String: Any] ?? [:]
                guard booking.text("status") == "in_progress", booking["location_enabled"] as? Bool != false,
                      ["admin", "caretaker"].contains(me.text("role")), walk.text("started_by") == me.text("id") else { stop(); return }
                start(bookingID: id)
            } catch {
                if let status = (error as? APIError)?.statusCode, [401, 403, 404, 409].contains(status) { stop() }
                else { statusMessage = "Połącz z internetem, aby wznowić zapisany spacer." }
            }
        }
    }
    func stop() {
        heartbeat?.cancel(); heartbeat = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        bookingID = nil
        isTracking = false
        queue.removeAll(); persist()
        UserDefaults.standard.removeObject(forKey: savedBookingKey)
        statusMessage = "Lokalizacja wyłączona"
    }
    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(queue), forKey: queueKey)
    }
    private func beginUpdates() {
        guard bookingID != nil else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isTracking = true
        statusMessage = manager.accuracyAuthorization == .reducedAccuracy ? "Włącz dokładną lokalizację, aby zapisywać trasę." : "Oczekiwanie na dokładny pomiar GPS…"
        if heartbeat == nil {
            heartbeat = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.sendPending()
                    do { try await Task.sleep(for: .seconds(15)) } catch { break }
                }
            }
        }
    }
    func flushBeforeEnding() async throws {
        guard !sending else { throw APIError.message("Trwa wysyłanie trasy. Spróbuj za chwilę.") }
        guard let id = bookingID else { return }
        sending = true; defer { sending = false }
        while !queue.isEmpty {
            try await uploadBatch(id: id)
        }
    }
    private func uploadBatch(id: String) async throws {
        let batch = Array(queue.prefix(100))
        guard !batch.isEmpty else { return }
        let data = try JSONEncoder().encode(batch)
        let objects = try JSONSerialization.jsonObject(with: data)
        _ = try await APIClient.shared.request("POST", "walks/\(id)/location", body: ["points": objects])
        guard bookingID == id else { return }
        let ids = Set(batch.map(\.client_point_id))
        queue.removeAll { ids.contains($0.client_point_id) }; persist()
        lastSentAt = Date()
        statusMessage = queue.isEmpty ? "Trasa zsynchronizowana • \(Date.now.formatted(date: .omitted, time: .shortened))" : "Wysyłanie zapisanej trasy: \(queue.count) punktów"
    }
    private func sendPending() async {
        guard !sending, let id = bookingID else { return }
        sending = true; defer { sending = false }
        do {
            let result = try await APIClient.shared.request("GET", "walks/\(id)")
            let b = result["booking"] as? [String: Any] ?? [:]
            guard b.text("status") == "in_progress", b["location_enabled"] as? Bool != false else { stop(); return }
            try await uploadBatch(id: id)
        } catch {
            guard bookingID == id else { return }
            if let status = (error as? APIError)?.statusCode, [401, 403, 404, 409].contains(status) {
                stop(); statusMessage = "Spacer lub sesja zakończone — GPS wyłączony."
            } else { statusMessage = "Brak sieci • zapisano na telefonie: \(queue.count) punktów" }
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard bookingID != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: beginUpdates()
        case .denied, .restricted: stop(); statusMessage = "Brak zgody na lokalizację."
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard bookingID != nil else { return }
        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 75 && abs(location.timestamp.timeIntervalSinceNow) <= 30 {
            queue.append(Point(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy, timestamp: ISO8601DateFormatter().string(from: location.timestamp), client_point_id: UUID().uuidString))
        }
        if queue.count > 10000 { queue.removeFirst(queue.count - 10000) }
        persist()
        Task { await sendPending() }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusMessage = "GPS: \(error.localizedDescription)"
    }
}
