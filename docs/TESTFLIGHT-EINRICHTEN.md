# PULSE ONE aufs iPhone bringen (TestFlight) – einmalige Einrichtung

Am besten am PC (Windows reicht). Dauer: etwa 15 Minuten. Danach baut und lädt GitHub jede neue Version selbst hoch.

## Schritt 1 – App-ID anlegen (developer.apple.com)
1. https://developer.apple.com/account/resources/identifiers/list öffnen
2. Blaues **+** neben „Identifiers“ → **App IDs** → Continue → **App** → Continue
3. Description: `PULSE ONE`
4. Bundle ID: **Explicit** und genau `de.sommerlabs.pulseone` eintragen
5. In der Liste „Capabilities“ das Häkchen bei **HealthKit** setzen (sonst nichts ändern) → **Continue** → **Register**
   (Falls du die App-ID schon ohne HealthKit angelegt hast: App-ID öffnen, HealthKit anhaken, **Save**.)

## Schritt 2 – App in App Store Connect anlegen
1. https://appstoreconnect.apple.com/apps öffnen
2. Blaues **+** → **Neue App**
3. Plattform: **iOS** · Name: `PULSE ONE` (falls vergeben: `PULSE ONE Sommer`) · Sprache: **Deutsch**
4. Bundle-ID: `de.sommerlabs.pulseone` auswählen · SKU: `pulseone`
5. Zugriff: **Voller Zugriff** → **Erstellen**

Die App wird dadurch **nicht** veröffentlicht. Sie ist nur für dich sichtbar.

## Schritt 3 – Schlüssel für GitHub erstellen
1. https://appstoreconnect.apple.com/access/integrations/api öffnen (Benutzer und Zugriff → Integrationen → App Store Connect API)
2. Beim ersten Mal: **Zugriff anfordern** bestätigen
3. **+** (Schlüssel generieren) → Name: `GitHub PULSE ONE` → Zugriff: **Admin** → Generieren
4. **Herunterladen** der Datei `AuthKey_XXXXXXXXXX.p8` (geht nur einmal!)
5. Notieren: **Schlüssel-ID** (in der Tabelle) und **Aussteller-ID** (oben über der Tabelle)

## Schritt 4 – Drei Geheimnisse in GitHub eintragen
1. https://github.com/email-blip/Pulse-one/settings/secrets/actions öffnen
2. **New repository secret**, dreimal:
   - Name `ASC_KEY_ID` → Wert: Schlüssel-ID
   - Name `ASC_ISSUER_ID` → Wert: Aussteller-ID
   - Name `ASC_KEY_P8` → Wert: die .p8-Datei mit dem Editor öffnen (Rechtsklick → Öffnen mit → Editor), **alles** markieren (Strg+A), kopieren, einfügen
3. Die .p8-Datei danach an einem sicheren Ort aufbewahren, nicht weitergeben

Bitte die Werte **nicht** in den Chat schreiben. Sie gehören nur in GitHub.

## Schritt 5 – TestFlight auf dem iPhone
1. App **TestFlight** aus dem App Store laden
2. Sobald Claude meldet „Build ist hochgeladen“: in App Store Connect → PULSE ONE → **TestFlight** → Interne Tests → Gruppe anlegen, dich selbst hinzufügen
3. Einladung auf dem iPhone in TestFlight annehmen → **Installieren**

Danach: QRing-App schließen, PULSE ONE öffnen, „Ring suchen“.
