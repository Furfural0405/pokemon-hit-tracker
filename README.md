# Pokémon Hit Tracker

Responsive React-/TypeScript-Web-App für Display-, Case- und Case-Case-Öffnungen mit getrennten Nutzerkonten, manueller Freigabe, garantierten Hits und FUR-/RGB-Auswertung.

## Sicherheits- und Projektstatus

**Quellcode im GitHub-Repository eingerichtet; noch nicht live bereitgestellt.** Für diese Version muss **ein neues, separates Supabase-Projekt** erstellt und die Datenbankmigration ausgeführt werden. Das bestehende Projekt `pokemon-pullrates` darf **nicht** durch die Migration überschrieben werden.

## Funktionen

- Startset: 30th Celebration – Simplified Chinese; später erweiterbare Sets.
- Display = 1 SAR + 2 Classics + 4 AR; Case = 12 Displays; Case-Case = 6 Cases = 72 Displays.
- Einzeln (1 Display) oder gemischt (mindestens 2 *vollständig ungeöffnete* Displays), auch über Case-Grenzen hinweg.
- Abschnitte einzeln manuell abschließen, danach weitere Abschnitte öffnen. Die Gesamtöffnung bleibt bis zum manuellen Abschluss offen.
- FUR-/RGB-Ereignisse pro Abschnitt ohne Obergrenze. Ein Hit aus einem Mischpool wird keinem einzelnen Display zugerechnet.
- Statistik: Zusatzhits, fertige Displays, Vergleich Einzeln/Gemischt, Detailübersicht der Öffnungen. Nur vollständig abgeschlossene und mit allen garantierten Hits protokollierte Abschnitte zählen in den Nenner der Hit-Rate.
- Registrieren, E-Mail bestätigen, warten auf manuelle Freigabe. Admin kann freigeben, ablehnen oder sperren. RLS trennt private Nutzerdaten.

## Einrichtung (neues Supabase-Projekt)

1. Ein **eigenes neues** Supabase-Projekt erstellen; Region möglichst in Europa wählen. Etwaige Kosten vor Bestätigung prüfen.
2. Unter **SQL Editor** die Datei `supabase/migrations/202610280001_hit_tracker_initial.sql` genau einmal ausführen (auf einem leeren Projekt). Alternativ per Supabase CLI als Migration anwenden.
3. Unter **Authentication → Providers → Email** E-Mail-Bestätigung aktivieren und eine geeignete SMTP-Konfiguration für Einladungs- und Bestätigungsmails einrichten. Der Status `approved` ist **zusätzlich** zur E-Mail-Bestätigung erforderlich.
4. **Admin einmalig initialisieren:** Melde dich zunächst selbst über die Webseite an und bestätige deine E-Mail. Sobald `app_profiles` deinen Benutzer enthält, im Supabase-SQL-Editor ausführen (E-Mail anpassen):

   ```sql
   update public.app_profiles set role='admin', status='approved'
   where id=(select id from auth.users where email='DEINE-EMAIL@DOMAIN.DE');
   ```

   Dieses SQL nur im vertrauenswürdigen Datenbank-Editor ausführen, nicht im Browser oder aus der App. Prüfe vorher die richtige E-Mail-Adresse. Es gibt **keine** automatische Administratorernennung für Erstregistrierungen.
5. **Authentication → URL Configuration:** Die produktive Website als Site URL und Redirect URL hinterlegen. Bei GitHub Pages z. B. `https://DEIN-GITHUB-NAME.github.io/pokemon-hit-tracker/`. Für lokale Entwicklung zusätzlich `http://localhost:5173` zulassen.
6. In **Project Settings / Connect** die **Project URL** und den **Publishable Key** (`sb_publishable_...`) ermitteln. Niemals Secret/Service-Role-Key in einem Frontend oder öffentlichen GitHub-Repository speichern.

## Lokale Entwicklung

```sh
npm install
cp .env.example .env
# .env bearbeiten: Projekt-URL und Publishable Key eintragen
npm run dev
```

Frontend auf `http://localhost:5173` öffnen. **Nicht** mit echten Nutzerkonten oder Daten produktiv gehen, bevor die Sicherheitsprüfung abgeschlossen ist.

## GitHub / Hosting

1. Das Repository ist bereits eingerichtet: https://github.com/Furfural0405/pokemon-hit-tracker (öffentlich).
2. Die Projektdateien befinden sich im Repository. Vor einem verlässlichen Produktionsrelease eine `package-lock.json` mit `npm install` erzeugen und committen – **ohne `.env`**.
3. Vite-Basis für GitHub Pages: `VITE_BASE_PATH=/pokemon-hit-tracker/` (siehe `.env.example`). Bei anderer Domain oder Repository-Benennung anpassen.
4. Das Workflow-Grundgerüst `.github/workflows/pages.yml` liegt bei. Vor dem ersten Deploy unter **Settings → Secrets and variables → Actions → Variables** `VITE_SUPABASE_URL` und `VITE_SUPABASE_PUBLISHABLE_KEY` eintragen (beide sind öffentlich verwendbare Clientwerte). Niemals Secret-Key eintragen. Unter **Settings → Pages** die Quelle **GitHub Actions** auswählen. Der Build und die Veröffentlichung starten beim Push auf `main`.
5. `npm install` in einer Umgebung mit Zugang zur npm-Registry ausführen und die entstehende **package-lock.json** committen; danach ist für Produktions-Builds `npm ci` vorzuziehen. Dieser Paketstand konnte offline nicht vollständig installiert werden und muss vor Produktivstart geprüft werden.
6. GitHub Pages kann das Frontend hosten, während Supabase Auth/DB bereitstellt.

## Datenmodell

- `app_profiles`: Benutzerrollen und Freigabestatus; Admin ist nur über vertrauenswürdige Datenbankinitialisierung bootstrap-fähig.
- `app_sets`: Regelkonfigurationen.
- `app_openings`: Verpackungsöffnung mit Snapshot der Set-Regeln.
- `app_displays`: eindeutige Displays mit Case- und Display-Nummer.
- `app_groups`: einzelne oder gemischte Öffnungsabschnitte (max. ein aktiver Abschnitt).
- `app_group_displays`: jedes Display kann nur einem Öffnungsabschnitt zugeordnet werden.
- `app_hit_events`: ein Datensatz je Hit, Zeitstempel und Korrektur durch Entfernen (nur bis Abschnittsabschluss).

Alle öffentlichen Tabellen nutzen Row-Level Security. Im Browser nur der Publishable Key. Datenbank-Trigger prüfen garantierte Höchstwerte, machen abgeschlossene Abschnitte schreibgeschützt und verhindern die Wiederverwendung von Displays.

## Noch offene Schritte vor Produktivbetrieb

- Das GitHub-Repository ist erstellt; das separate Supabase-Projekt muss noch angelegt werden (Kostenfreigabe ausstehend).
- Migration im **neuen** Projekt anwenden, Verbindung konfigurieren und die Auth-Einstellungen prüfen.
- E-Mail-Zustellung sowie Admin-Bootstrap testen.
- Komplette Integrationstests mit zwei Konten: `pending` vs. `approved`, Fremdzugriff, parallele Counter-Updates, Registrierung, Sperrung, Case-Case-Grenzen.
- GitHub Pages bereitstellen und End-to-End-Test auf der echten Domain durchführen.

## Wichtige Auswertungsregeln

Case-übergreifende Mischung wird dem Gesamtvorgang, **nicht** willkürlich einem einzelnen Case zugeordnet. Statistik zählt abgeschlossene Boosterpools pro Anzahl ihrer Displays, nicht als eine einzelne Displayöffnung. Ein einmaliges Case-Case zählt als **eine** Case-Case-Öffnung, nicht zusätzlich als sechs separate Case-Öffnungen. Die Zahl erfasster FUR/RGB-Ereignisse kann größer sein als die Zahl der Displays; „Hits je 100 Displays“ ist daher keine Wahrscheinlichkeit.

## Datenschutz

E-Mail-Adressen der Registrierenden sind nur dem jeweiligen Benutzer und Admin sichtbar. Es gibt kein eingebautes Tracking oder Drittanbieter-Analytics. Beachte bei öffentlicher Verwendung eigene Impressums-/Datenschutzhinweispflichten und eine passende Datenschutzerklärung.
## Stand 28.10.2026

Die GitHub-Dateien wurden durch ChatGPT direkt hochgeladen und auf GitHub verifiziert. Die neue React-/TypeScript-Anwendung wurde noch nicht vollständig mit npm gebaut oder End-to-End getestet. Der Supabase-Projekt-Neuanlage wird von der API eine Kostenbestätigung abverlangt (Abfrage: 0 USD/Monat); bis zur Bestätigung wurde keine bestehende Datenbank verändert. GitHub Pages ist noch nicht konfiguriert bzw. live bestätigt.
