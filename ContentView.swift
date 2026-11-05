import SwiftUI
import MapKit

private enum AppStyle {
    static let green = Color(red: 0.16, green: 0.39, blue: 0.31)
    static let mint = Color(red: 0.91, green: 0.95, blue: 0.92)
    static let ink = Color(red: 0.12, green: 0.20, blue: 0.17)
    static let muted = Color(red: 0.45, green: 0.51, blue: 0.47)
    static let canvas = Color(red: 0.96, green: 0.97, blue: 0.95)
}

struct ContentView: View {
    @StateObject private var session = SessionStore()

    var body: some View {
        Group {
            if session.isLoading {
                ProgressView("Ładowanie…")
            } else if let user = session.user {
                MainTabView(session: session, user: user)
                    .id(user.id)
            } else {
                AuthView(session: session)
            }
        }
        .tint(AppStyle.green)
        .task { await session.restore() }
    }
}

// MARK: - Logowanie i rejestracja

private struct AuthView: View {
    @ObservedObject var session: SessionStore
    @State private var isRegister = false
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppStyle.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(AppStyle.green)
                            .frame(width: 82, height: 82)
                            .background(AppStyle.mint, in: Circle())
                            .padding(.top, 34)
                        Text("Na spacerze")
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppStyle.ink)
                        Text("Dobre spacery. Spokojna głowa.")
                            .foregroundStyle(AppStyle.muted)

                        VStack(alignment: .leading, spacing: 14) {
                            Text(isRegister ? "Utwórz konto klienta" : "Witaj ponownie")
                                .font(.title2.bold())
                            if isRegister {
                                TextField("Imię", text: $firstName).textContentType(.givenName)
                                TextField("Nazwisko", text: $lastName).textContentType(.familyName)
                                TextField("Telefon", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                                TextField("Adres odbioru psa", text: $address)
                            }
                            TextField("Adres e-mail", text: $email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .autocorrectionDisabled()
                            SecureField("Hasło", text: $password)
                                .textContentType(isRegister ? .newPassword : .password)
                            if let error {
                                Text(error).foregroundStyle(.red).font(.footnote)
                            } else if let sessionError = session.errorMessage {
                                Text(sessionError).foregroundStyle(.red).font(.footnote)
                            }
                            Button {
                                Task { await submit() }
                            } label: {
                                HStack {
                                    if busy { ProgressView().tint(.white) }
                                    Text(isRegister ? "Utwórz konto" : "Zaloguj się").bold()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy)

                            Button(isRegister ? "Mam już konto — zaloguj się" : "Nie mam konta — rejestracja") {
                                isRegister.toggle()
                                error = nil
                            }
                            .frame(maxWidth: .infinity)
                            .font(.subheadline)
                        }
                        .textFieldStyle(.roundedBorder)
                        .padding(22)
                        .background(.white, in: RoundedRectangle(cornerRadius: 22))
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            if isRegister {
                guard !firstName.trimmingCharacters(in: .whitespaces).isEmpty,
                      !phone.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw APIError.message("Podaj imię i numer telefonu.")
                }
                try await session.register(
                    firstName: firstName, lastName: lastName, email: email,
                    phone: phone, address: address, password: password
                )
            } else {
                try await session.login(email: email, password: password)
            }
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Główna nawigacja, różne role

private struct MainTabView: View {
    @ObservedObject var session: SessionStore
    let user: AppUser
    @StateObject private var locationManager = WalkLocationManager()
    @State private var bookings: [[String: Any]] = []
    @State private var pets: [[String: Any]] = []
    @State private var notifications: [[String: Any]] = []
    @State private var stats: [String: Any] = [:]
    @State private var activeWalk: [String: Any]?
    @State private var showBookingForm = false
    @State private var loading = false
    @State private var error: String?
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(
                    user: user, bookings: bookings, pets: pets, stats: stats,
                    activeWalk: activeWalk,
                    onBook: { showBookingForm = true },
                    onRefresh: refresh
                )
                .toolbar { commonToolbar }
            }
            .tabItem { Label("Start", systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                BookingListView(bookings: bookings, isStaff: user.isStaff,
                                locationManager: locationManager, onChanged: refresh)
                    .toolbar { commonToolbar }
            }
            .tabItem { Label(user.isStaff ? "Zlecenia" : "Rezerwacje", systemImage: "calendar") }
            .tag(1)

            if user.isStaff {
                NavigationStack {
                    ActiveWalkView(activeWalk: activeWalk, locationManager: locationManager, onRefresh: refresh)
                        .toolbar { commonToolbar }
                }
                .tabItem { Label("Spacer LIVE", systemImage: "location.fill") }
                .tag(2)
            } else {
                NavigationStack {
                    PetsView(pets: pets, onChanged: refresh)
                        .toolbar { commonToolbar }
                }
                .tabItem { Label("Psy", systemImage: "pawprint.fill") }
                .tag(2)
            }

            NavigationStack {
                NotificationsView(items: notifications, onChanged: refresh)
                    .toolbar { commonToolbar }
            }
            .tabItem { Label("Alerty", systemImage: "bell") }
            .tag(3)

            NavigationStack {
                ProfileView(user: user, session: session, onChanged: refresh)
                    .toolbar { commonToolbar }
            }
            .tabItem { Label("Profil", systemImage: "person.crop.circle") }
            .tag(4)
        }
        .task {
            locationManager.resumeSavedWalkIfNeeded()
            await refresh()
        }
        .refreshable { await refresh() }
        .sheet(isPresented: $showBookingForm) {
            BookingFormView(onCreated: {
                showBookingForm = false
                selectedTab = 1
                Task { await refresh() }
            })
        }
        .alert("Informacja", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    @ToolbarContentBuilder
    private var commonToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 7) {
                Image(systemName: "pawprint.fill").foregroundStyle(AppStyle.green)
                Text("Na spacerze").font(.headline).foregroundStyle(AppStyle.ink)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if loading { ProgressView() }
            else { Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") } }
        }
    }

    @MainActor
    private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            let bookingPath = user.isStaff ? "admin/bookings" : "bookings"
            bookings = try await APIClient.shared.request("GET", bookingPath).objects("bookings")
            notifications = try await APIClient.shared.request("GET", "notifications").objects("notifications")
            let walkResponse = try await APIClient.shared.request("GET", "walks/active")
            activeWalk = walkResponse["activeWalk"] as? [String: Any]
            if !user.isStaff {
                pets = try await APIClient.shared.request("GET", "pets").objects("pets")
            } else {
                stats = try await APIClient.shared.request("GET", "admin/overview")["stats"] as? [String: Any] ?? [:]
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
            if (error as? APIError)?.statusCode == 401 { session.logout() }
        }
    }
}

// MARK: - Dashboard

private struct DashboardView: View {
    let user: AppUser
    let bookings: [[String: Any]]
    let pets: [[String: Any]]
    let stats: [String: Any]
    let activeWalk: [String: Any]?
    let onBook: () -> Void
    let onRefresh: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Cześć, \(user.firstName)! 👋").font(.title.bold()).foregroundStyle(AppStyle.ink)
                    Text(user.isStaff ? "Panel opiekuna" : "Strefa klienta").foregroundStyle(AppStyle.muted)
                }
                if user.isStaff {
                    HStack(spacing: 10) {
                        StatTile(title: "Nowe", value: stats.text("pendingCount", fallback: "0"), icon: "bell.badge")
                        StatTile(title: "Zaplanowane", value: stats.text("confirmedCount", fallback: "0"), icon: "calendar")
                    }
                    HStack(spacing: 10) {
                        StatTile(title: "W trakcie", value: stats.text("inProgressCount", fallback: "0"), icon: "figure.walk")
                        StatTile(title: "Klienci", value: stats.text("clientCount", fallback: "0"), icon: "person.2")
                    }
                } else {
                    HStack(spacing: 12) {
                        StatTile(title: "Moje psy", value: "\(pets.count)", icon: "pawprint")
                        StatTile(title: "Rezerwacje", value: "\(bookings.count)", icon: "calendar")
                    }
                    Button(action: onBook) {
                        Label("Zarezerwuj spacer", systemImage: "plus.circle.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let active = activeWalk, let booking = active["booking"] as? [String: Any] {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Spacer trwa", systemImage: "location.fill").font(.headline).foregroundStyle(AppStyle.green)
                        Text((booking["pet"] as? [String: Any])?.text("name", fallback: "Aktywny spacer") ?? booking.text("pet_name", fallback: "Aktywny spacer"))
                            .font(.title3.bold())
                        Text("Możesz otworzyć szczegóły w zakładce \(user.isStaff ? "Spacer LIVE" : "Rezerwacje").")
                            .font(.subheadline).foregroundStyle(AppStyle.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(AppStyle.mint, in: RoundedRectangle(cornerRadius: 18))
                }

                Text(user.isStaff ? "Ostatnie zlecenia" : "Najbliższe rezerwacje")
                    .font(.title3.bold()).foregroundStyle(AppStyle.ink)
                if bookings.isEmpty {
                    ContentUnavailableView("Brak rezerwacji", systemImage: "calendar", description: Text(user.isStaff ? "Nowe zlecenia pojawią się tutaj." : "Gdy zarezerwujesz spacer, zobaczysz go w tym miejscu."))
                } else {
                    ForEach(Array(bookings.prefix(4).enumerated()), id: \.offset) { _, item in
                        BookingSummaryCard(booking: item)
                    }
                }
            }
            .padding(18)
        }
        .background(AppStyle.canvas)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await onRefresh() }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(AppStyle.green)
            Text(value).font(.title.bold()).foregroundStyle(AppStyle.ink)
            Text(title).font(.caption).foregroundStyle(AppStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct BookingSummaryCard: View {
    let booking: [String: Any]
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(booking.text("pet_name", fallback: (booking["pet"] as? [String: Any])?.text("name", fallback: "Spacer") ?? "Spacer"))
                    .font(.headline)
                Spacer()
                StatusLabel(status: booking.text("status"))
            }
            Text("\(booking.text("scheduled_date")) • \(booking.text("scheduled_time"))")
                .font(.subheadline).foregroundStyle(AppStyle.muted)
            Text("\(booking.text("duration_minutes", fallback: "45")) min • \(booking.text("price_pln", fallback: "—")) zł")
                .font(.caption).foregroundStyle(AppStyle.muted)
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct StatusLabel: View {
    let status: String
    private var title: String {
        ["pending": "Oczekuje", "confirmed": "Potwierdzona", "scheduled": "Zaplanowana",
         "in_progress": "W trakcie", "completed": "Zakończona", "cancelled": "Anulowana"][status] ?? status
    }
    var body: some View {
        Text(title).font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 5)
            .background(status == "in_progress" ? Color.green.opacity(0.15) : AppStyle.mint, in: Capsule())
            .foregroundStyle(AppStyle.green)
    }
}

// MARK: - Rezerwacje i działania po stronie opiekuna/klienta

private struct BookingListView: View {
    let bookings: [[String: Any]]
    let isStaff: Bool
    @ObservedObject var locationManager: WalkLocationManager
    let onChanged: () async -> Void

    var body: some View {
        List {
            if bookings.isEmpty {
                ContentUnavailableView("Brak rezerwacji", systemImage: "calendar", description: Text("Tutaj pojawią się rezerwacje i zlecenia."))
            }
            ForEach(Array(bookings.enumerated()), id: \.offset) { _, booking in
                NavigationLink {
                    BookingDetailView(booking: booking, isStaff: isStaff, locationManager: locationManager, onChanged: onChanged)
                } label: {
                    BookingSummaryCard(booking: booking).listRowInsets(EdgeInsets())
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .padding(.vertical, 5)
            }
        }
        .listStyle(.plain)
        .background(AppStyle.canvas)
        .navigationTitle(isStaff ? "Zlecenia" : "Rezerwacje")
        .refreshable { await onChanged() }
    }
}

private struct BookingDetailView: View {
    let booking: [String: Any]
    let isStaff: Bool
    @ObservedObject var locationManager: WalkLocationManager
    let onChanged: () async -> Void
    @State private var error: String?
    @State private var busy = false

    private var bookingID: String { booking.text("id") }
    private var petName: String { (booking["pet"] as? [String: Any])?.text("name", fallback: "Pies") ?? booking.text("pet_name", fallback: "Pies") }

    var body: some View {
        List {
            Section("Szczegóły spaceru") {
                LabeledContent("Pies", value: petName)
                LabeledContent("Termin", value: "\(booking.text("scheduled_date")) • \(booking.text("scheduled_time"))")
                LabeledContent("Czas", value: "\(booking.text("duration_minutes")) min")
                LabeledContent("Cena", value: "\(booking.text("price_pln")) zł")
                LabeledContent("Adres odbioru", value: booking.text("pickup_address", fallback: "—"))
                LabeledContent("Status", value: booking.text("status"))
                if !booking.text("notes").isEmpty { Text(booking.text("notes")) }
            }

            Section("Kontakt i trasa") {
                NavigationLink {
                    ChatView(bookingID: bookingID)
                } label: {
                    Label("Otwórz czat", systemImage: "message")
                }
                NavigationLink {
                    WalkTrackingView(bookingID: bookingID, locationManager: locationManager)
                } label: {
                    Label("Zobacz trasę spaceru", systemImage: "map")
                }
            }

            if isStaff {
                Section("Panel opiekuna") {
                    if booking.text("status") == "in_progress" {
                        Button {
                            Task { await endWalk() }
                        } label: {
                            Label("Zakończ spacer", systemImage: "stop.circle.fill")
                        }
                        .disabled(busy)
                        if locationManager.isTracking {
                            Label(locationManager.statusMessage, systemImage: "location.fill")
                                .font(.footnote).foregroundStyle(AppStyle.green)
                        } else {
                            Button {
                                locationManager.start(bookingID: bookingID)
                            } label: {
                                Label("Wznów / włącz GPS w tle", systemImage: "location.circle")
                            }
                        }
                    } else {
                        Button { Task { await updateStatus("confirmed") } } label: {
                            Label("Potwierdź rezerwację", systemImage: "checkmark.circle")
                        }
                        Button { Task { await startWalk() } } label: {
                            Label("Rozpocznij spacer i GPS", systemImage: "figure.walk")
                        }
                        Button(role: .destructive) { Task { await updateStatus("cancelled") } } label: {
                            Label("Anuluj zlecenie", systemImage: "xmark.circle")
                        }
                    }
                }
            } else if !["completed", "cancelled", "in_progress"].contains(booking.text("status")) {
                Section {
                    Button("Anuluj rezerwację", role: .destructive) {
                        Task { await cancelBooking() }
                    }
                    .disabled(busy)
                }
            }

            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Szczegóły")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if busy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
    }

    private func startWalk() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await APIClient.shared.request("POST", "walks/\(bookingID)/start", body: [:])
            locationManager.start(bookingID: bookingID)
            await onChanged()
        } catch { self.error = error.localizedDescription }
    }

    private func endWalk() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await APIClient.shared.request("POST", "walks/\(bookingID)/end", body: [:])
            locationManager.stop()
            await onChanged()
        } catch { self.error = error.localizedDescription }
    }

    private func updateStatus(_ status: String) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await APIClient.shared.request("PATCH", "admin/bookings/\(bookingID)/status", body: ["status": status])
            await onChanged()
        } catch { self.error = error.localizedDescription }
    }

    private func cancelBooking() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await APIClient.shared.request("POST", "bookings/\(bookingID)/cancel", body: ["reason": "Anulowano w aplikacji iOS"])
            await onChanged()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Formularz rezerwacji

private struct BookingFormView: View {
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pets: [[String: Any]] = []
    @State private var pricing: [[String: Any]] = []
    @State private var petID = ""
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var time = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now) ?? .now
    @State private var duration = 45
    @State private var address = ""
    @State private var notes = ""
    @State private var terms = false
    @State private var locationConsent = false
    @State private var parentalConsent = false
    @State private var loading = false
    @State private var error: String?

    private var price: String {
        let item = pricing.first { Int($0.number("duration")) == duration }
        return item.map { "\(Int($0.number("price"))) zł" } ?? ([30: "40 zł", 45: "55 zł", 60: "70 zł"][duration] ?? "—")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pies") {
                    Picker("Wybierz psa", selection: $petID) {
                        Text("Wybierz…").tag("")
                        ForEach(Array(pets.enumerated()), id: \.offset) { _, pet in
                            Text(pet.text("name")).tag(pet.text("id"))
                        }
                    }
                }
                Section("Termin") {
                    DatePicker("Data", selection: $date, in: Date()..., displayedComponents: .date)
                    DatePicker("Godzina", selection: $time, displayedComponents: .hourAndMinute)
                    Picker("Długość spaceru", selection: $duration) {
                        Text("30 minut").tag(30)
                        Text("45 minut").tag(45)
                        Text("60 minut").tag(60)
                    }
                    LabeledContent("Cena", value: price)
                }
                Section("Odbiór") {
                    TextField("Dokładny adres odbioru", text: $address)
                    TextField("Uwagi dla opiekuna", text: $notes, axis: .vertical)
                }
                Section("Zgody") {
                    Toggle("Akceptuję regulamin (wymagane)", isOn: $terms)
                    Toggle("Zgoda na lokalizację podczas spaceru", isOn: $locationConsent)
                    Toggle("Zgoda rodzica/opiekuna prawnego", isOn: $parentalConsent)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if loading { ProgressView() } else { Text("Wyślij rezerwację").bold() }
                            Spacer()
                        }
                    }
                    .disabled(loading || petID.isEmpty || address.trimmingCharacters(in: .whitespaces).count < 5 || !terms)
                }
            }
            .navigationTitle("Nowa rezerwacja")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Zamknij") { dismiss() } } }
            .task { await loadFormData() }
        }
    }

    private func loadFormData() async {
        do {
            pets = try await APIClient.shared.request("GET", "pets").objects("pets")
            pricing = try await APIClient.shared.request("GET", "availability/pricing").objects("pricing")
            if petID.isEmpty { petID = pets.first?.text("id") ?? "" }
        } catch { error = error.localizedDescription }
    }

    private func submit() async {
        loading = true; error = nil
        defer { loading = false }
        let dateFormatter = DateFormatter(); dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter(); timeFormatter.dateFormat = "HH:mm"
        do {
            _ = try await APIClient.shared.request("POST", "bookings", body: [
                "pet_id": petID,
                "scheduled_date": dateFormatter.string(from: date),
                "scheduled_time": timeFormatter.string(from: time),
                "duration_minutes": duration,
                "pickup_address": address,
                "notes": notes,
                "consent_terms": terms,
                "consent_location": locationConsent,
                "consent_parental": parentalConsent
            ])
            onCreated()
        } catch { error = error.localizedDescription }
    }
}

// MARK: - Psy

private struct PetsView: View {
    let pets: [[String: Any]]
    let onChanged: () async -> Void
    @State private var showAdd = false

    var body: some View {
        List {
            ForEach(Array(pets.enumerated()), id: \.offset) { _, pet in
                VStack(alignment: .leading, spacing: 5) {
                    Label(pet.text("name", fallback: "Pies"), systemImage: "pawprint.fill").font(.headline)
                    Text("\(pet.text("breed", fallback: "Mieszaniec")) • \(pet.text("age", fallback: "Wiek niepodany"))")
                        .font(.subheadline).foregroundStyle(AppStyle.muted)
                    if !pet.text("temperament").isEmpty { Text(pet.text("temperament")).font(.caption).foregroundStyle(AppStyle.muted) }
                }
                .padding(.vertical, 5)
            }
        }
        .navigationTitle("Moje psy")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { PetFormView { showAdd = false; Task { await onChanged() } } }
        .refreshable { await onChanged() }
    }
}

private struct PetFormView: View {
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var breed = ""
    @State private var age = ""
    @State private var size = "medium"
    @State private var temperament = ""
    @State private var fears = ""
    @State private var leash = ""
    @State private var notes = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Podstawowe informacje") {
                    TextField("Imię psa", text: $name)
                    TextField("Rasa", text: $breed)
                    TextField("Wiek", text: $age)
                    Picker("Wielkość", selection: $size) {
                        Text("Mały").tag("small"); Text("Średni").tag("medium"); Text("Duży").tag("large")
                    }
                }
                Section("Informacje dla opiekuna") {
                    TextField("Charakter", text: $temperament)
                    TextField("Lęki / obawy", text: $fears)
                    TextField("Smycz / szelki", text: $leash)
                    TextField("Dodatkowe uwagi", text: $notes, axis: .vertical)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button { Task { await save() } } label: {
                    HStack { Spacer(); if busy { ProgressView() } else { Text("Zapisz profil psa").bold() }; Spacer() }
                }.disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .navigationTitle("Dodaj psa")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Zamknij") { dismiss() } } }
        }
    }

    private func save() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await APIClient.shared.request("POST", "pets", body: [
                "name": name, "breed": breed, "age": age, "size": size,
                "temperament": temperament, "fears": fears,
                "leash_info": leash, "notes": notes
            ])
            onCreated()
        } catch { error = error.localizedDescription }
    }
}

// MARK: - Powiadomienia

private struct NotificationsView: View {
    let items: [[String: Any]]
    let onChanged: () async -> Void

    var body: some View {
        List {
            if items.isEmpty { ContentUnavailableView("Brak powiadomień", systemImage: "bell") }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button {
                    Task {
                        _ = try? await APIClient.shared.request("PATCH", "notifications/\(item.text("id"))/read", body: [:])
                        await onChanged()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.text("title")).font(.headline).foregroundStyle(AppStyle.ink)
                            Spacer()
                            if !item.flag("is_read") { Circle().fill(AppStyle.green).frame(width: 8, height: 8) }
                        }
                        Text(item.text("body")).font(.subheadline).foregroundStyle(AppStyle.muted)
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Powiadomienia")
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button("Oznacz wszystkie") {
                Task { _ = try? await APIClient.shared.request("POST", "notifications/read-all", body: [:]); await onChanged() }
            }.font(.caption)
        } }
        .refreshable { await onChanged() }
    }
}

// MARK: - Profil

private struct ProfileView: View {
    let user: AppUser
    @ObservedObject var session: SessionStore
    let onChanged: () async -> Void
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section("Konto") {
                Text(user.email)
                LabeledContent("Rola", value: user.role == "client" ? "Klient" : (user.role == "admin" ? "Administrator" : "Opiekun"))
            }
            Section("Dane kontaktowe") {
                TextField("Imię", text: $firstName)
                TextField("Nazwisko", text: $lastName)
                TextField("Telefon", text: $phone).keyboardType(.phonePad)
                TextField("Adres", text: $address)
                Button("Zapisz zmiany") { Task { await save() } }
            }
            if let message { Text(message).font(.footnote) }
            Section {
                Button("Wyloguj się", role: .destructive) { session.logout() }
            }
        }
        .navigationTitle("Profil")
        .task {
            firstName = user.firstName; lastName = user.lastName
            phone = user.phone; address = user.address
        }
    }

    private func save() async {
        do {
            _ = try await APIClient.shared.request("PUT", "users/profile", body: [
                "first_name": firstName, "last_name": lastName,
                "phone": phone, "address": address
            ])
            message = "Profil zapisany. Zaloguj się ponownie, aby odświeżyć dane nagłówka."
            await onChanged()
        } catch { message = error.localizedDescription }
    }
}

// MARK: - Czat (REST + odświeżanie)

private struct ChatView: View {
    let bookingID: String
    @State private var messages: [[String: Any]] = []
    @State private var input = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.text("sender_name", fallback: "Użytkownik")).font(.caption.bold()).foregroundStyle(AppStyle.green)
                            Text(item.text("content")).foregroundStyle(AppStyle.ink)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    }
                }.padding()
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal) }
            HStack {
                TextField("Napisz wiadomość…", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button { Task { await send() } } label: { Image(systemName: "paperplane.fill") }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .background(AppStyle.canvas)
        .navigationTitle("Czat")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { messages = try await APIClient.shared.request("GET", "messages/\(bookingID)").objects("messages"); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func send() async {
        let content = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await APIClient.shared.request("POST", "messages/\(bookingID)", body: ["content": content])
            input = ""
            await load()
        } catch { error = error.localizedDescription }
    }
}

// MARK: - Spacer LIVE i natywna mapa Apple

private struct ActiveWalkView: View {
    let activeWalk: [String: Any]?
    @ObservedObject var locationManager: WalkLocationManager
    let onRefresh: () async -> Void

    var body: some View {
        Group {
            if let booking = activeWalk?["booking"] as? [String: Any] {
                WalkTrackingView(bookingID: booking.text("id"), locationManager: locationManager)
            } else {
                ContentUnavailableView("Brak aktywnego spaceru", systemImage: "location", description: Text("Gdy rozpoczniesz spacer z poziomu zlecenia, trasa pojawi się tutaj."))
            }
        }
        .navigationTitle("Spacer LIVE")
        .task { await onRefresh() }
    }
}

private struct WalkTrackingView: View {
    let bookingID: String
    @ObservedObject var locationManager: WalkLocationManager
    @State private var points: [[String: Any]] = []
    @State private var error: String?

    private var coordinates: [CLLocationCoordinate2D] {
        points.compactMap { point in
            let lat = point.number("latitude", fallback: .nan)
            let lon = point.number("longitude", fallback: .nan)
            guard lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if coordinates.isEmpty {
                ContentUnavailableView("Brak punktów trasy", systemImage: "map", description: Text("Punkty GPS pojawią się po rozpoczęciu spaceru."))
            } else {
                Map {
                    if coordinates.count > 1 {
                        MapPolyline(coordinates: coordinates).stroke(AppStyle.green, lineWidth: 5)
                    }
                    if let first = coordinates.first { Marker("Start", coordinate: first).tint(.green) }
                    if let last = coordinates.last { Marker("Ostatnia pozycja", coordinate: last).tint(.orange) }
                }
                .mapControlVisibility(.visible)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label(locationManager.statusMessage, systemImage: "location.fill")
                    .font(.footnote).foregroundStyle(locationManager.isTracking ? AppStyle.green : AppStyle.muted)
                Text("Punktów trasy: \(points.count)").font(.caption).foregroundStyle(AppStyle.muted)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Button("Odśwież trasę") { Task { await load() } }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial)
        }
        .navigationTitle("Trasa spaceru")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            points = try await APIClient.shared.request("GET", "walks/\(bookingID)").objects("points")
            error = nil
        } catch { error = error.localizedDescription }
    }
}
