import SwiftUI

struct LegalLinksView: View {
    var body: some View {
        HStack {
            NavigationLink("Prywatność") { LegalDocumentView(documentID: "privacy") }
            NavigationLink("Regulamin") { LegalDocumentView(documentID: "terms") }
        }.font(.footnote)
    }
}
struct LegalDocumentView: View {
    let documentID: String
    @State private var document: [String: Any] = [:]
    @State private var error: String?
    var body: some View {
        List {
            Text("Wersja \(document.text("version"))").font(.caption)
            if document.flag("draft") { Text("Wzór do uzupełnienia przez operatora przed uruchomieniem usługi.").foregroundStyle(.orange) }
            ForEach(Array(document.objects("sections").enumerated()), id: \.offset) { _, section in
                Section(section.text("title")) { Text(section.text("body")).textSelection(.enabled) }
            }
            if let error { Text(error).foregroundStyle(.red); Button("Ponów") { Task { await load() } } }
        }
        .navigationTitle(document.text("title", fallback: "Dokument"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        do { document = try await APIClient.shared.request("GET", "legal/\(documentID)", authenticated: false)["document"] as? [String: Any] ?? [:]; error = nil }
        catch { self.error = error.localizedDescription }
    }
}
struct ServicesView: View {
    let role: String
    var body: some View {
        List {
            if role == "client" {
                Section { NavigationLink { SubscriptionsView() } label: { Label("Pakiety spacerów", systemImage: "pawprint.circle.fill") } }
            }
            if role == "admin" {
                Section("Administracja") {
                    NavigationLink("Pakiety i płatności") { AdminConsoleView(page: "subscriptions", title: "Pakiety i płatności") }
                    NavigationLink("Użytkownicy i role") { AdminConsoleView(page: "users", title: "Użytkownicy") }
                    NavigationLink("Dni wolne") { AdminConsoleView(page: "blackouts", title: "Dni wolne") }
                    NavigationLink("Zgłoszenia klientów") { AdminConsoleView(page: "requests", title: "Zgłoszenia") }
                    NavigationLink("Historia operacji") { AdminConsoleView(page: "audit", title: "Historia operacji") }
                }
            }
            Section("Kontakt") { NavigationLink { SupportView() } label: { Label("Pomoc i dane", systemImage: "bubble.left.and.text.bubble.right") } }
            Section("Dokumenty") {
                NavigationLink("Polityka prywatności") { LegalDocumentView(documentID: "privacy") }
                NavigationLink("Regulamin usług") { LegalDocumentView(documentID: "terms") }
                NavigationLink("Regulamin pakietów") { LegalDocumentView(documentID: "subscriptions") }
            }
        }.navigationTitle("Twoja strefa")
    }
}
private func statusLabel(_ value: String) -> String {
    ["pending": "Oczekuje na płatność", "active": "Aktywny", "cancelled": "Zamknięty", "expired": "Wygasł", "open": "Otwarte", "resolved": "Odpowiedź"][value] ?? value
}
struct SubscriptionsView: View {
    @State private var plans: [[String: Any]] = []
    @State private var subscriptions: [[String: Any]] = []
    @State private var terms = false
    @State private var busy = false
    @State private var message: String?
    @State private var cancelID: String?
    var body: some View {
        List {
            Section {
                Text("Pakiety na 30 dni. Płatność uzgadniasz z administratorem; aktywacja po jej potwierdzeniu. Brak automatycznego odnawiania i obciążania karty.")
            }
            if let message { Section { Text(message).font(.callout) } }
            if busy { ProgressView() }
            Section("Twoje pakiety") {
                if subscriptions.isEmpty { Text("Nie masz jeszcze pakietu.").foregroundStyle(.secondary) }
                ForEach(Array(subscriptions.reversed().enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(s.text("name")).font(.headline)
                        Text(statusLabel(s.text("status")))
                        Text("Pozostało \(Int(s.number("remaining_walks"))) z \(Int(s.number("walks"))) spacerów").font(.title3.bold())
                        if let date = ISO8601DateFormatter().date(from: s.text("expires_at")) { Text("Ważny do \(date.formatted(date: .abbreviated, time: .shortened))").font(.footnote) }
                        else if !s.text("expires_at").isEmpty { Text("Ważny do \(s.text("expires_at").prefix(10))") }
                        if s["cancel_requested_at"] != nil { Text("Rezygnacja zgłoszona — oczekuje na rozliczenie").foregroundStyle(.orange) }
                        else if ["pending", "active"].contains(s.text("status")) {
                            Button(s.text("status") == "pending" ? "Anuluj zgłoszenie" : "Zgłoś rezygnację", role: .destructive) { cancelID = s.text("id") }.disabled(busy)
                        }
                    }.padding(.vertical, 8)
                }
            }
            Section("Wybierz rytm spacerów") {
                ForEach(Array(plans.enumerated()), id: \.offset) { _, plan in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(plan.text("name")).font(.title3.bold())
                        Text("\(Int(plan.number("price"))) zł").font(.largeTitle.bold()).foregroundStyle(Color(red: 0.16, green: 0.39, blue: 0.31))
                        Text("\(Int(plan.number("walks"))) spacerów × 30 min • 30 dni")
                        Button("Zgłoś pakiet") { Task { await perform(path: "subscriptions", body: ["plan_id": plan.text("id"), "consent_terms": true]) } }.buttonStyle(.borderedProminent).disabled(!terms || busy)
                    }.padding(.vertical, 12)
                }
                Toggle("Akceptuję regulamin usług i pakietów", isOn: $terms)
                LegalLinksView()
                NavigationLink("Regulamin pakietów") { LegalDocumentView(documentID: "subscriptions") }
            }
        }
        .navigationTitle("Pakiety spacerów")
        .task { await load() }
        .refreshable { await load() }
        .alert("Zgłosić rezygnację?", isPresented: Binding(get: { cancelID != nil }, set: { if !$0 { cancelID = nil } })) {
            Button("Zgłoś", role: .destructive) { if let id = cancelID { Task { await perform(path: "subscriptions/\(id)/cancel", body: [:]) } }; cancelID = nil }
            Button("Wróć", role: .cancel) { cancelID = nil }
        } message: { Text("Aktywny pakiet pozostaje ważny do rozliczenia lub końca okresu. Administrator uzgodni ewentualny zwrot.") }
    }
    private func load() async {
        do {
            subscriptions = try await APIClient.shared.request("GET", "subscriptions").objects("subscriptions")
            plans = try await APIClient.shared.request("GET", "subscriptions/plans").objects("plans")
        } catch { message = error.localizedDescription }
    }
    private func perform(path: String, body: [String: Any]) async {
        busy = true; defer { busy = false }
        do { message = try await APIClient.shared.request("POST", path, body: body).text("message"); await load() }
        catch { message = error.localizedDescription }
    }
}
struct SupportView: View {
    @State private var type = "help"
    @State private var input = ""
    @State private var requests: [[String: Any]] = []
    @State private var message: String?
    @State private var busy = false
    var body: some View {
        Form {
            Section("Nowe zgłoszenie") {
                Picker("Sprawa", selection: $type) {
                    Text("Pytanie").tag("help")
                    Text("Reklamacja").tag("complaint")
                    Text("Odstąpienie od umowy").tag("withdrawal")
                    Text("Kopia danych").tag("privacy_access")
                    Text("Usunięcie konta / danych").tag("privacy_delete")
                }
                TextField("Opisz sprawę i podaj numer rezerwacji, jeśli dotyczy", text: $input, axis: .vertical).lineLimit(3...8)
                Button("Wyślij zgłoszenie") { Task { await submit() } }.disabled(busy || input.trimmingCharacters(in: .whitespacesAndNewlines).count < 5)
                Text("Usunięcie konta wymaga realizacji zgłoszenia przez administratora.").font(.footnote)
            }
            if let message { Text(message) }
            Section("Twoje sprawy") {
                ForEach(Array(requests.reversed().enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(statusLabel(r.text("status"))).font(.headline)
                        Text(r.text("message"))
                        if !r.text("reply").isEmpty { Text(r.text("reply")).foregroundStyle(.green) }
                    }
                }
            }
        }.navigationTitle("Pomoc i dane").task { await load() }.refreshable { await load() }
    }
    private func load() async {
        do { requests = try await APIClient.shared.request("GET", "support").objects("requests") }
        catch { message = error.localizedDescription }
    }
    private func submit() async {
        busy = true; defer { busy = false }
        do { message = try await APIClient.shared.request("POST", "support", body: ["type": type, "message": input]).text("message"); input = ""; await load() }
        catch { message = error.localizedDescription }
    }
}
struct AdminConsoleView: View {
    let page: String
    let title: String
    @State private var rows: [[String: Any]] = []
    @State private var input = ""
    @State private var date = ""
    @State private var message: String?
    @State private var busy = false
    @State private var confirmation: String?
    @State private var pendingPath = ""
    @State private var pendingBody: [String: Any] = [:]
    var body: some View {
        List {
            if busy { ProgressView() }
            if let message { Text(message).font(.callout) }
            if page == "requests" { TextField("Odpowiedź na wybrane zgłoszenie", text: $input, axis: .vertical) }
            if page == "subscriptions" {
                Text("Aktywuj po otrzymaniu płatności. Zwroty wykonuj osobno.")
                TextField("Ustalenia rezygnacji / zwrotu", text: $input, axis: .vertical)
            }
            if page == "blackouts" {
                TextField("Dzień wolny RRRR-MM-DD", text: $date)
                Button("Zablokuj dzień") { Task { await perform("POST", "admin/blackouts", ["date": date]) } }.disabled(date.count != 10 || busy)
                Text("Istniejące zlecenia odwołaj osobno funkcją „Nie mogę przyjść”.").font(.footnote)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 10) {
                    if page == "users" {
                        Text("\(r.text("first_name")) \(r.text("last_name"))").font(.headline)
                        Text(r.text("email")); Text("\(r.text("role")) • \(r.flag("is_active") ? "Aktywne" : "Zablokowane")")
                        if r.text("role") != "admin" {
                            Button(r.flag("is_active") ? "Zablokuj konto" : "Odblokuj konto") { Task { await perform("PATCH", "admin/users/\(r.text("id"))", ["is_active": !r.flag("is_active")]) } }
                            Button(r.text("role") == "client" ? "Nadaj rolę opiekuna" : "Zmień na klienta") { Task { await perform("PATCH", "admin/users/\(r.text("id"))", ["role": r.text("role") == "client" ? "caretaker" : "client"]) } }
                        }
                    } else if page == "subscriptions" {
                        Text(r.text("user_name")).font(.headline)
                        Text("\(r.text("name")) • \(Int(r.number("price"))) zł")
                        Text("\(statusLabel(r.text("status"))) • saldo \(Int(r.number("remaining_walks")))")
                        if r["cancel_requested_at"] != nil { Text("Rezygnacja zgłoszona").foregroundStyle(.orange) }
                        if r.text("status") == "pending" {
                            Button("Potwierdź wpłatę i aktywuj") {
                                pendingPath = "admin/subscriptions/\(r.text("id"))/activate"; pendingBody = ["payment_confirmed": true]
                                confirmation = "Potwierdzasz wpłatę \(Int(r.number("price"))) zł od \(r.text("user_name"))? Aktywacja rozpocznie 30 dni ważności."
                            }
                        }
                        if ["pending", "active"].contains(r.text("status")) {
                            Button("Zamknij i zapisz ustalenia", role: .destructive) {
                                pendingPath = "admin/subscriptions/\(r.text("id"))/close"; pendingBody = ["reason": input]
                                confirmation = "Zamknąć pakiet? Ustalenia: \(input). Zwrot wykonaj osobno."
                            }.disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                        }
                    } else if page == "blackouts" {
                        Text(r.text("date")).font(.headline)
                        Button("Odblokuj") { Task { await perform("DELETE", "admin/blackouts/\(r.text("id"))", [:]) } }
                    } else if page == "requests" {
                        Text("\(r.text("user_name")) • \(r.text("type"))").font(.headline)
                        Text(r.text("message")); Text(statusLabel(r.text("status")))
                        if !r.text("reply").isEmpty { Text(r.text("reply")) }
                        if r.text("status") == "open" {
                            Button("Wyślij tę odpowiedź i zamknij") { Task { await perform("PATCH", "admin/requests/\(r.text("id"))", ["reply": input]) } }.disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                        }
                    } else {
                        Text(r.text("action")).font(.headline); Text(r.text("created_at")).font(.caption); Text(r.text("entity_id")); Text(r.text("details"))
                    }
                }.padding(.vertical, 8).disabled(busy).buttonStyle(.borderless)
            }
            if rows.isEmpty && !busy { Text("Brak wpisów.").foregroundStyle(.secondary) }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
        .alert("Potwierdź", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            Button("Potwierdź") { let path = pendingPath, body = pendingBody; confirmation = nil; Task { await perform("POST", path, body) } }
            Button("Wróć", role: .cancel) { confirmation = nil }
        } message: { Text(confirmation ?? "") }
    }
    private func load() async {
        do {
            let path = page == "blackouts" ? "availability" : "admin/\(page)"
            let key = page == "blackouts" ? "blackouts" : (page == "audit" ? "events" : page)
            rows = try await APIClient.shared.request("GET", path).objects(key)
        } catch { message = error.localizedDescription }
    }
    private func perform(_ method: String, _ path: String, _ body: [String: Any]) async {
        busy = true; defer { busy = false }
        do { message = try await APIClient.shared.request(method, path, body: body).text("message"); input = ""; await load() }
        catch { message = error.localizedDescription }
    }
}
