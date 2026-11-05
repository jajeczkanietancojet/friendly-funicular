# Na spacerze — natywna aplikacja iOS (SwiftUI)

To jest zestaw plików źródłowych do dodania do nowego projektu iOS w Xcode. Nie używa WebView.
Aplikacja korzysta z istniejącego backendu Express pod `/api`.

## Pliki

- `ContentView.swift` — interfejs SwiftUI: logowanie/rejestracja, panel klienta i pracownika, rezerwacje, psy, powiadomienia, profil, czat REST i mapa trasy.
- `APIClient.swift` — komunikacja HTTP z backendem, Bearer JWT i bezpieczne przechowywanie tokenu w Keychain.
- `SessionStore.swift` — sesja, logowanie, rejestracja i rozpoznawanie roli `client`, `caretaker`, `admin`.
- `WalkLocationManager.swift` — natywne śledzenie CoreLocation z aktualizacją backendu.
- `InfoPlist-keys.txt` — wymagane klucze Info.plist i tryb pracy w tle.

## Utworzenie projektu w Xcode

1. Na Macu otwórz Xcode i wybierz **File → New → Project → iOS → App**.
2. Product Name: `NaSpacerze`; Interface: **SwiftUI**; Language: **Swift**.
3. Ustaw minimalny deployment target na **iOS 17.0** (używany jest natywny MapKit `MapPolyline`).
4. Usuń wygenerowany `ContentView.swift` i dodaj wszystkie cztery pliki `.swift` do targetu aplikacji.
5. W `Info` targetu dodaj klucze z `InfoPlist-keys.txt`.
6. W **Signing & Capabilities → + Capability → Background Modes** zaznacz **Location updates**.
7. Ustaw `API_BASE_URL` na sam adres serwera, bez końcowego `/api`, np. `https://api.twojadomena.pl`.
8. Uruchom aplikację na iPhonie. Do testów GPS w tle używaj prawdziwego iPhone’a, nie tylko symulatora.

## Backend i endpointy

Adres API jest budowany jako `API_BASE_URL + /api/ + ścieżka`. Aplikacja używa istniejących tras:

- `POST auth/login`, `POST auth/register`, `GET auth/me`
- `GET bookings`, `POST bookings`, `POST bookings/:id/cancel`
- `GET pets`, `POST pets`
- `GET notifications`, `PATCH notifications/:id/read`, `POST notifications/read-all`
- `GET availability/pricing`
- `GET admin/bookings`, `GET admin/overview`, `PATCH admin/bookings/:id/status`
- `GET walks/active`, `GET walks/:bookingId`, `POST walks/:bookingId/start`, `POST walks/:bookingId/location`, `POST walks/:bookingId/end`
- `GET messages/:bookingId`, `POST messages/:bookingId`
- `PUT users/profile`

Rola użytkownika z `auth/me` decyduje, czy pojawia się interfejs klienta (`client`), czy pracownika (`admin`, `caretaker`).

## Śledzenie w tle na iOS

Opiekun uruchamia spacer z widocznego ekranu aplikacji. `WalkLocationManager` rozpoczyna standardowe aktualizacje CoreLocation, ustawia `allowsBackgroundLocationUpdates = true` i przesyła punkty GPS do `POST /api/walks/:bookingId/location` co najmniej co 5 sekund (zależnie od dostaw GPS). Wymagane są wpisy lokalizacyjne w Info.plist, Background Mode `location` oraz zgoda użytkownika.

iOS nie daje gwarancji nieprzerwanego śledzenia po ręcznym wymuszeniu zamknięcia aplikacji przez użytkownika, wyłączeniu usług lokalizacji lub odebraniu zgody. Dla aktywnego trackingu aplikacja powinna pozostać uruchomiona w tle; system wyświetla wskaźnik lokalizacji. Uprawnienie „Zawsze” zwiększa możliwości dostarczania zdarzeń w tle, ale nie znosi ograniczeń systemu.

## Ważne ograniczenia tej wersji

- Czat działa przez REST i można go odświeżać; nie ma jeszcze natychmiastowych zdarzeń Socket.IO.
- Powiadomienia są pobierane z endpointu backendu; APNs push wymaga osobnej konfiguracji po stronie Apple i backendu.
- Mapa korzysta z natywnego MapKit i punktów z `/api/walks/:bookingId`.
- Projektu nie skompilowano tutaj — do budowania aplikacji iOS potrzebny jest Mac z Xcode. Przed publikacją uruchom testy na urządzeniu i sprawdź komunikaty walidacji App Store, zwłaszcza uzasadnienie użycia lokalizacji w tle.
