#!/usr/bin/env python3
"""
Chief of Staff — Vault Watcher
Surveille les daily notes Obsidian pour détecter les priorités complétées
et recalcule la prochaine priorité via Claude CLI.
"""

import subprocess
import hashlib
import time
import os
import sys
import logging
from datetime import datetime
from pathlib import Path

# --- Configuration ---

VAULT_DAILY_DIR = "/root/obsidian-vault/5 TOOLS/Notes quotidienne"
MEMORY_DIR = "/root/claude-memory"
PRIMER_PATH = os.path.join(MEMORY_DIR, "primer.md")
PRIORITY_ENGINE_PATH = "/root/claude-heartbeat/priority-engine.md"
TELEGRAM_SCRIPT = "/root/claude-heartbeat/telegram.sh"
LOG_PATH = "/root/claude-heartbeat/watcher.log"
DEBOUNCE_SECONDS = 15
VAULT_RETRY_SECONDS = 60
CLAUDE_MAX_TURNS = 8
CLAUDE_MODEL = "sonnet"

# --- Logging ---

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [watcher] %(levelname)s — %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.FileHandler(LOG_PATH, encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("watcher")

# --- Cache d'état ---
# Stocke le hash du contenu + le nombre de checkboxes cochées par fichier
_state_cache: dict[str, dict] = {}


def compute_file_state(filepath: str) -> dict | None:
    """Lit un fichier et retourne son état (hash, checkboxes cochées, contenu)."""
    try:
        content = Path(filepath).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        log.warning("Impossible de lire %s : %s", filepath, exc)
        return None

    content_hash = hashlib.sha256(content.encode("utf-8")).hexdigest()

    # Compter les checkboxes cochées : [x] ou [FAIT]
    checked_count = 0
    checked_lines = []
    for line in content.splitlines():
        stripped = line.strip()
        if stripped.startswith("- [x]") or stripped.startswith("- [X]"):
            checked_count += 1
            checked_lines.append(stripped)
        elif "[FAIT]" in stripped:
            checked_count += 1
            checked_lines.append(stripped)

    return {
        "hash": content_hash,
        "checked_count": checked_count,
        "checked_lines": checked_lines,
        "content": content,
    }


def read_file_safe(filepath: str) -> str:
    """Lit un fichier en toute sécurité, retourne chaîne vide si erreur."""
    try:
        return Path(filepath).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        log.warning("Impossible de lire %s : %s", filepath, exc)
        return ""


def send_telegram(message: str) -> None:
    """Envoie un message Telegram via le helper script."""
    try:
        subprocess.run(
            ["bash", "-c", 'source "$1" && send_message "$2"', "--", TELEGRAM_SCRIPT, message],
            timeout=30,
            check=False,
        )
        log.info("Telegram envoyé : %s", message[:80])
    except subprocess.TimeoutExpired:
        log.error("Timeout envoi Telegram")
    except Exception as exc:
        log.error("Erreur envoi Telegram : %s", exc)


def call_claude_recalculate(daily_content: str) -> str | None:
    """
    Appelle Claude CLI pour recalculer la prochaine priorité.
    Retourne la réponse texte ou None en cas d'erreur.
    """
    primer_content = read_file_safe(PRIMER_PATH)
    priority_engine_content = read_file_safe(PRIORITY_ENGINE_PATH)

    prompt = f"""Tu es le Chief of Staff de Pierre. Il vient de terminer une priorité.

=== DAILY NOTE ACTUELLE ===
{daily_content}

=== PRIMER ===
{primer_content}

=== PRIORITY ENGINE ===
{priority_engine_content}

Pierre a terminé la priorité marquée [FAIT]. Recalcule les priorités restantes.
Si les 3 priorités du jour sont faites, propose une 4e basée sur le primer.
Écris UNIQUEMENT la nouvelle priorité au format du Priority Engine."""

    try:
        result = subprocess.run(
            [
                "claude",
                "-p", prompt,
                "--model", CLAUDE_MODEL,
                "--output-format", "text",
                "--allowedTools", "Read,Write,Edit",
                "--max-turns", str(CLAUDE_MAX_TURNS),
            ],
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )

        if result.returncode != 0:
            log.error("Claude CLI erreur (code %d) : %s", result.returncode, result.stderr[:200])
            return None

        response = result.stdout.strip()
        if not response:
            log.error("Claude CLI a retourné une réponse vide")
            return None

        log.info("Claude a recalculé la priorité (%d caractères)", len(response))
        return response

    except subprocess.TimeoutExpired:
        log.error("Claude CLI timeout après 120s")
        return None
    except FileNotFoundError:
        log.error("Claude CLI introuvable — vérifier l'installation")
        return None
    except Exception as exc:
        log.error("Erreur inattendue Claude CLI : %s", exc)
        return None


def process_daily_note_change(filepath: str) -> None:
    """
    Compare l'état actuel d'une daily note avec le cache.
    Si une priorité a été complétée, recalcule via Claude et notifie.
    """
    new_state = compute_file_state(filepath)
    if new_state is None:
        return

    old_state = _state_cache.get(filepath)

    # Première observation de ce fichier — on cache sans agir
    if old_state is None:
        _state_cache[filepath] = new_state
        log.info("Première observation de %s (%d checkboxes cochées)", filepath, new_state["checked_count"])
        return

    # Pas de changement réel (même hash) — bruit Syncthing
    if new_state["hash"] == old_state["hash"]:
        log.debug("Pas de changement réel dans %s", filepath)
        return

    # Vérifier si de nouvelles checkboxes ont été cochées
    new_checked = new_state["checked_count"]
    old_checked = old_state["checked_count"]

    # Mettre à jour le cache dans tous les cas
    _state_cache[filepath] = new_state

    if new_checked <= old_checked:
        log.info("Changement dans %s mais pas de nouvelle checkbox cochée (%d -> %d)", filepath, old_checked, new_checked)
        return

    log.info("Priorité complétée détectée dans %s (%d -> %d checkboxes)", filepath, old_checked, new_checked)

    # Trouver les nouvelles lignes cochées
    old_set = set(old_state["checked_lines"])
    newly_completed = [line for line in new_state["checked_lines"] if line not in old_set]

    if newly_completed:
        log.info("Nouvelles tâches complétées : %s", newly_completed)

    # Appeler Claude pour recalculer
    response = call_claude_recalculate(new_state["content"])

    if response is None:
        log.error("Impossible de recalculer la priorité — Claude a échoué")
        send_telegram("Erreur : impossible de recalculer la priorite apres completion.")
        return

    # Notifier Pierre
    # Extraire la première ligne significative de la réponse comme résumé
    summary_lines = [line.strip() for line in response.splitlines() if line.strip()]
    summary = summary_lines[0] if summary_lines else "Voir la daily note"

    # Tronquer pour Telegram si nécessaire
    if len(summary) > 200:
        summary = summary[:197] + "..."

    send_telegram(f"Priorite completee. Prochaine : {summary}")
    log.info("Cycle terminé — notification envoyée")


def check_inotifywait() -> bool:
    """Vérifie que inotifywait est installé."""
    try:
        result = subprocess.run(
            ["which", "inotifywait"],
            capture_output=True,
            text=True,
            check=False,
        )
        return result.returncode == 0
    except Exception:
        return False


def wait_for_vault() -> None:
    """Attend que le répertoire du vault soit disponible (Syncthing pas encore prêt)."""
    while not os.path.isdir(VAULT_DAILY_DIR):
        log.warning("Répertoire %s introuvable — Syncthing pas prêt ? Retry dans %ds", VAULT_DAILY_DIR, VAULT_RETRY_SECONDS)
        time.sleep(VAULT_RETRY_SECONDS)
    log.info("Répertoire vault trouvé : %s", VAULT_DAILY_DIR)


def initialize_cache() -> None:
    """Pré-charge l'état de toutes les daily notes existantes."""
    log.info("Initialisation du cache des daily notes...")
    count = 0
    for entry in Path(VAULT_DAILY_DIR).iterdir():
        if entry.suffix == ".md" and entry.is_file():
            state = compute_file_state(str(entry))
            if state is not None:
                _state_cache[str(entry)] = state
                count += 1
    log.info("Cache initialisé avec %d fichiers", count)


def run_watcher() -> None:
    """
    Boucle principale : lance inotifywait et traite les événements
    avec debounce de 15 secondes.
    """
    log.info("Démarrage de inotifywait sur %s", VAULT_DAILY_DIR)

    process = subprocess.Popen(
        [
            "inotifywait",
            "-m",              # monitor (boucle infinie)
            "-e", "modify",    # uniquement les modifications
            "--format", "%w%f",
            VAULT_DAILY_DIR + "/",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    # Dictionnaire pour le debounce : filepath -> timestamp du dernier événement
    pending_events: dict[str, float] = {}

    try:
        while True:
            # Lire les événements de inotifywait (non-bloquant via select-like approach)
            # On utilise un timeout court pour pouvoir vérifier le debounce
            import select

            ready, _, _ = select.select([process.stdout], [], [], 1.0)

            if ready:
                line = process.stdout.readline()
                if not line:
                    # inotifywait s'est arrêté
                    log.error("inotifywait s'est terminé de manière inattendue")
                    break

                filepath = line.strip()
                if not filepath.endswith(".md"):
                    continue

                log.debug("Événement inotify : %s", filepath)
                pending_events[filepath] = time.time()

            # Vérifier les événements en attente (debounce)
            now = time.time()
            processed = []
            for filepath, event_time in pending_events.items():
                if now - event_time >= DEBOUNCE_SECONDS:
                    log.info("Debounce écoulé pour %s — traitement", filepath)
                    try:
                        process_daily_note_change(filepath)
                    except Exception as exc:
                        log.error("Erreur traitement %s : %s", filepath, exc)
                    processed.append(filepath)

            for filepath in processed:
                del pending_events[filepath]

            # Vérifier que le processus est toujours vivant
            if process.poll() is not None:
                log.error("inotifywait s'est arrêté (code %d)", process.returncode)
                break

    except KeyboardInterrupt:
        log.info("Arrêt demandé (SIGINT)")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()


def main() -> None:
    """Point d'entrée principal."""
    log.info("=== Chief of Staff — Vault Watcher démarré ===")

    # Vérifier inotifywait
    if not check_inotifywait():
        log.error("inotifywait non installé. Installer avec : apt-get install -y inotify-tools")
        sys.exit(1)

    # Attendre que le vault soit disponible
    wait_for_vault()

    # Initialiser le cache avec l'état actuel
    initialize_cache()

    # Boucle de surveillance avec redémarrage automatique
    while True:
        try:
            run_watcher()
        except Exception as exc:
            log.error("Erreur dans la boucle principale : %s", exc)

        log.info("Redémarrage du watcher dans 10 secondes...")
        time.sleep(10)


if __name__ == "__main__":
    main()
