# NaSpacerze — natywny iOS

Pełna instrukcja i lista zmian: [README projektu](../README.md).

- SwiftUI i MapKit; bez WebView. Minimum iOS 17.
- Ustaw `API_BASE_URL` w `project.yml`, wygeneruj projekt przez `xcodegen generate`.
- `Info.plist` zawiera tryb `UIBackgroundModes: location`, opis zgody lokalizacyjnej i dostęp do sieci lokalnej. Nie usuwaj tego pliku.
- Uruchomienie GPS: potwierdzone zlecenie → Rozpocznij spacer. Przy rezerwacji musi być włączone udostępnianie GPS. Zgoda „Podczas używania” umożliwia kontynuowanie rozpoczętej lokalizacji przy włączonym trybie tła; system pokazuje wskaźnik. Wymuszone zamknięcie aplikacji może przerwać śledzenie.
- Pakiety, pomoc, dokumenty i administracja znajdują się w Profilu.
- Główny workflow `.github/workflows/build.yml` buduje symulator i unsigned IPA. Plik IPA do instalacji na iPhonie wymaga podpisu.

Dla publicznej wersji użyj HTTPS i usuń szerokie dopuszczenie HTTP z `NSAppTransportSecurity` po ustawieniu domeny produkcyjnej.
