#!/bin/bash
# Jarvis-Installer für den Mac (Jarvis Version 21, erstellt am 06.10.2026).
# Aufruf im Terminal:   curl -fsSL <Link>/jarvis-install.sh | bash
# Enthält keine Schlüssel und keine persönlichen Daten. Die Schlüssel fragt es ab und speichert sie nur auf diesem Mac.

PAKET_URL="${JARVIS_PAKET_URL:-https://raw.githubusercontent.com/lukykempf96-lang/Jarvis-Installer/main/jarvis-paket.tar.gz}"
PAKET_SHA256="f0dd9e6ac542dda625e5824c9be5b3400cd0bdd3f547bc157531f000a8eab662"
ZIEL="$HOME/Downloads/Jarvis"   # nur hier findet Jarvis später seine Updates

main() {
set -uo pipefail
TTY=/dev/tty                     # Antworten kommen von der Tastatur, nicht aus dem Skript
fett() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
hinweis() { printf '  %s\n' "$1"; }
stopp() { printf '\n\033[31m✗ %s\033[0m\n' "$1"; exit 1; }
frage() { local a; read -r -p "  $1 " a < "$TTY" || true; printf '%s' "$a"; }
geheim() { local a; read -r -s -p "  $1 " a < "$TTY" || true; echo > "$TTY"; printf '%s' "$a" | tr -d '[:space:]'; }
ja() { local a; a="$(frage "$1 [j/n]")"; [[ "$a" =~ ^[jJyY] ]]; }

clear 2>/dev/null || true
echo "=============================================="
echo "   Jarvis installieren (Version 21)"
echo "=============================================="
[ "$(uname)" = "Darwin" ] || stopp "Dieses Skript ist nur für den Mac."
[ -r "$TTY" ] || stopp "Bitte direkt im Terminal ausführen."
[ "$PAKET_URL" != "HIER-DEN-LINK-EINTRAGEN" ] || stopp "In diesem Skript ist noch kein Link zum Jarvis-Paket eingetragen."

# 1. Apple-Befehlszeilentools (Python, Swift, git)
fett "1/7  Apple-Befehlszeilentools"
if ! xcode-select -p >/dev/null 2>&1; then
    hinweis "Es öffnet sich gleich ein Fenster von Apple: auf „Installieren“ klicken und warten."
    xcode-select --install >/dev/null 2>&1 || true
    hinweis "Ich warte, bis die Installation fertig ist (das kann 5 bis 20 Minuten dauern) ..."
    for _ in $(seq 1 240); do xcode-select -p >/dev/null 2>&1 && break; sleep 10; done
    xcode-select -p >/dev/null 2>&1 || stopp "Die Befehlszeilentools fehlen noch. Nach der Installation den Befehl nochmal einfügen."
fi
ok "Befehlszeilentools vorhanden"

# 2. Homebrew und Python
fett "2/7  Homebrew und Python"
BREW=""
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && BREW="$b" && break; done
if [ -z "$BREW" ]; then
    hinweis "Homebrew (die Paketverwaltung für den Mac) fehlt. Damit bekommt Jarvis ein aktuelles Python."
    if ja "Homebrew jetzt installieren? (fragt nach deinem Mac-Passwort)"; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < "$TTY" \
            || hinweis "Homebrew ließ sich nicht installieren, ich nehme das Python von Apple."
        for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && BREW="$b" && break; done
    fi
fi
if [ -n "$BREW" ]; then
    eval "$("$BREW" shellenv)"
    if ! command -v python3.12 >/dev/null 2>&1; then
        hinweis "Python 3.12 wird installiert ..."
        "$BREW" install python@3.12 >/dev/null 2>&1 || hinweis "Python über Homebrew ging nicht, ich nehme das Python von Apple."
    fi
    ok "Homebrew vorhanden"
fi
PY=""
for c in python3.13 python3.12 python3.11 python3.10 python3; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null; then
        PY="$(command -v "$c")"; break
    fi
done
[ -n "$PY" ] || stopp "Kein Python 3.9 oder neuer gefunden."
ok "Python: $("$PY" --version 2>&1)"

if [ ! -d "/Applications/Google Chrome.app" ] && [ ! -d "$HOME/Applications/Google Chrome.app" ]; then
    hinweis "Google Chrome fehlt (das Jarvis-Fenster und die Spracherkennung brauchen es)."
    if [ -n "$BREW" ] && ja "Google Chrome jetzt installieren?"; then
        "$BREW" install --cask google-chrome >/dev/null 2>&1 && ok "Google Chrome installiert" \
            || hinweis "Bitte Chrome selbst von google.com/chrome installieren."
    else
        hinweis "Bitte Chrome von google.com/chrome installieren, das geht auch später."
    fi
else
    ok "Google Chrome vorhanden"
fi

# 3. Programm laden und prüfen
fett "3/7  Jarvis laden"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fL --progress-bar "$PAKET_URL" -o "$TMP/jarvis.tar.gz" < /dev/null || stopp "Das Jarvis-Paket ließ sich nicht laden. Internet und Link prüfen."
SUMME="$(shasum -a 256 "$TMP/jarvis.tar.gz" | cut -d' ' -f1)"
[ "$SUMME" = "$PAKET_SHA256" ] || stopp "Das Paket ist nicht das erwartete (Prüfsumme passt nicht). Abgebrochen, sicherheitshalber."
tar -xzf "$TMP/jarvis.tar.gz" -C "$TMP" || stopp "Das Paket ließ sich nicht entpacken."
ok "Paket geladen und geprüft"

# 4. Programmordner einrichten
fett "4/7  Programmordner $ZIEL"
UPDATE=0
if [ -d "$ZIEL" ]; then
    hinweis "Es gibt schon einen Jarvis in $ZIEL."
    if ja "Diesen Jarvis auf den neuen Stand bringen? Schlüssel, Haushaltsbuch und eigene Daten bleiben"; then
        UPDATE=1
        pkill -f "uvicorn backend.main" 2>/dev/null || true
        pkill -f backend.clap_daemon 2>/dev/null || true
        (cd "$TMP/Jarvis" && tar -cf - .) | (cd "$ZIEL" && tar -xf -) || stopp "Kopieren hat nicht geklappt."
    else
        stopp "Nichts verändert. Den alten Ordner erst umbenennen, dann den Befehl nochmal einfügen."
    fi
else
    mkdir -p "$(dirname "$ZIEL")"
    mv "$TMP/Jarvis" "$ZIEL" || stopp "Der Ordner ließ sich nicht anlegen."
fi
xattr -dr com.apple.quarantine "$ZIEL" 2>/dev/null || true
ok "Programmdateien eingerichtet (mit allen eigenen Funktionen)"

# 5. Schlüssel und Einstellungen
fett "5/7  Schlüssel und Einstellungen"
cd "$ZIEL" || stopp "Ordner fehlt."
umask 077
NEUE_ENV=0
if [ -f .env ] && grep -q '^ANTHROPIC_API_KEY=..' .env; then
    ok "Schlüssel sind schon eingetragen"
    ja "Trotzdem neue Schlüssel eingeben?" && NEUE_ENV=1
else
    NEUE_ENV=1
fi
if [ "$NEUE_ENV" = 1 ]; then
    hinweis "Anthropic-Schlüssel (Jarvis' Gehirn): console.anthropic.com -> API Keys -> Create Key -> kopieren."
    hinweis "Hier mit ⌘V einfügen. Man sieht beim Einfügen nichts, das ist Absicht. Dann Enter."
    while true; do
        KEY="$(geheim "Anthropic-Schlüssel:")"
        case "$KEY" in sk-ant-*) ;; *) hinweis "Das sieht nicht wie ein Anthropic-Schlüssel aus (beginnt mit sk-ant-)."; continue ;; esac
        CODE="$(printf 'header = "x-api-key: %s"\nheader = "anthropic-version: 2023-06-01"\n' "$KEY" \
                | curl -s -o /dev/null -w '%{http_code}' --config - https://api.anthropic.com/v1/models || echo 000)"
        if [ "$CODE" = "200" ]; then ok "Schlüssel funktioniert"; break; fi
        if [ "$CODE" = "401" ]; then hinweis "Anthropic lehnt diesen Schlüssel ab. Bitte nochmal kopieren."; continue; fi
        hinweis "Konnte den Schlüssel nicht prüfen (Code $CODE), ich speichere ihn trotzdem."; break
    done
    EKEY="$(geheim "ElevenLabs-Schlüssel für die Jarvis-Stimme (freiwillig, sonst nur Enter):")"
    NAME="$(frage "Wie heißt du? (so spricht Jarvis dich an)")"
    STADT="$(frage "Deine Stadt (für Wetter und Wege):")"
    [ -f .env ] || cp .env.example .env
    KEY="$KEY" EKEY="$EKEY" NAME="$NAME" STADT="$STADT" /usr/bin/python3 - <<'PYEOF'
import os, re
p = ".env"
s = open(p, encoding="utf-8").read()
def setze(name, wert, s):
    if not wert:
        return s
    zeile = f"{name}={wert}"
    return re.sub(rf"^{name}=.*$", lambda m: zeile, s, flags=re.M) if re.search(rf"^{name}=", s, re.M) else s.rstrip("\n") + "\n" + zeile + "\n"
for name, env in (("ANTHROPIC_API_KEY", "KEY"), ("ELEVENLABS_API_KEY", "EKEY"), ("JARVIS_NAME", "NAME"), ("JARVIS_CITY", "STADT")):
    s = setze(name, os.environ.get(env, "").strip(), s)
open(p, "w", encoding="utf-8").write(s)
PYEOF
    unset KEY EKEY
    chmod 600 .env
    ok "Gespeichert in $ZIEL/.env (nur für dich lesbar, nie weitergeben)"
fi
umask 022

# 6. Programmteile installieren
fett "6/7  Programmteile installieren (5 bis 15 Minuten)"
bash install.sh --update < "$TTY" || stopp "Die Installation ist stehen geblieben (Fehler siehe oben). Einfach den Befehl nochmal einfügen."
venv/bin/python -m backend.eigene > "$TMP/eigene.txt" 2>&1
if grep -q "FEHLER" "$TMP/eigene.txt"; then
    hinweis "Diese eigenen Funktionen melden einen Fehler (die anderen laufen trotzdem):"
    grep "FEHLER" "$TMP/eigene.txt" | sed 's/^/    /'
else
    ok "Alle eigenen Funktionen sind bereit ($(grep -c '^ok .*\.py' "$TMP/eigene.txt") Funktionen)"
fi

# 7. Berechtigungen und Start
fett "7/7  Berechtigungen"
cat <<'TEXT'
  macOS fragt beim ersten Start mehrmals nach. Immer „Erlauben“ bzw. „OK“ klicken.
  Von Hand einschalten unter Systemeinstellungen -> Datenschutz & Sicherheit:
    • Mikrofon ............................ Terminal und Google Chrome
    • Kalender (Vollzugriff), Erinnerungen, Kontakte ... Terminal
    • Festplattenvollzugriff .............. Terminal (Nachrichten, Kontakte, schnelles Mail-Lesen)
    • Automation .......................... Terminal -> Mail, Google Chrome, Kontakte, Terminal
    • Bildschirm- & Systemaudioaufnahme ... Terminal („Was ist auf meinem Bildschirm?“)
    • Lokales Netzwerk .................... Terminal (Handy-Anzeige, Handy-Mikro)
    • Bedienungshilfen .................... braucht Jarvis normalerweise nicht
  Nach jeder Änderung: „Jarvis neu starten.command“ im Jarvis-Ordner doppelklicken.
  Mail, Kalender und Nachrichten müssen in den Apple-Apps eingerichtet sein.
TEXT
if ja "Die Datenschutz-Einstellungen jetzt öffnen?"; then
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone" 2>/dev/null || true
fi

fett "Fertig!"
hinweis "Jarvis liegt in $ZIEL. Starten: Doppelklick auf „Jarvis.command“, dann zweimal klatschen oder „Hey Jarvis“ sagen."
hinweis "Eine ausführliche Anleitung steht in eigene/INSTALLATIONSANLEITUNG-MAC.txt."
if ja "Jarvis jetzt starten?"; then
    open "$ZIEL/Jarvis.command"
    hinweis "Jarvis startet in einem eigenen Terminal-Fenster. Dieses Fenster kannst du schließen."
fi
}

main "$@"
