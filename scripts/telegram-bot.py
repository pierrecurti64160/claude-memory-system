#!/usr/bin/env python3
"""
Telegram bot qui pilote Claude Code avec une session persistante.
Self-healing : refresh token auto si Claude CLI echoue.
Commandes Chief of Staff : fait, quoi, status, recap, cherche.
"""
import json, subprocess, time, os, sys, urllib.request, urllib.parse, tempfile, re
from datetime import datetime

# --- Twitter Engine ---
sys.path.insert(0, "/opt/twitter-engine")
try:
    from src.telegram_commands import is_twitter_command
    TWITTER_ENGINE_AVAILABLE = True
except ImportError:
    TWITTER_ENGINE_AVAILABLE = False
    print("Twitter Engine non disponible")
# --- Fin Twitter Engine ---

BOT_TOKEN = "8647578786:AAHf8sknMnDr0dAWWAk0dJLCrHZot3rRQ-U"
CHAT_ID = 2002390235
API = f"https://api.telegram.org/bot{BOT_TOKEN}"
MEMORY_DIR = "/root/claude-memory"
OFFSET_FILE = "/root/claude-heartbeat/telegram-offset"
PROJECTS_DIR = "/root/projects"
SESSION_FILE = "/root/claude-heartbeat/telegram-session-id"
REFRESH_SCRIPT = "/root/claude-heartbeat/refresh-auth.sh"
VAULT_DIR = "/root/obsidian-vault"
DAILY_DIR = f"{VAULT_DIR}/5 TOOLS/Notes quotidienne"
PRIORITY_ENGINE = "/root/claude-heartbeat/priority-engine.md"
DEBRIEF_DIR = "/root/claude-heartbeat/debriefs"

# Whisper
import whisper
print("Loading Whisper...")
whisper_model = whisper.load_model("base")
print("Whisper ready.")

# Compteur d'echecs consecutifs Claude CLI
cli_fail_count = 0
MAX_CLI_FAILS = 3


# ---------------------------------------------------------------------------
# Fonctions utilitaires
# ---------------------------------------------------------------------------

def api_call(method, data=None):
    url = f"{API}/{method}"
    if data:
        data = urllib.parse.urlencode(data).encode()
    try:
        req = urllib.request.Request(url, data=data)
        with urllib.request.urlopen(req, timeout=35) as r:
            return json.loads(r.read())
    except Exception as e:
        print(f"API error: {e}")
        return {"ok": False}

def send_message(text):
    for i in range(0, len(text), 4000):
        chunk = text[i:i+4000]
        api_call("sendMessage", {
            "chat_id": CHAT_ID,
            "text": chunk,
            "disable_web_page_preview": "true"
        })

def download_file(file_id):
    info = api_call("getFile", {"file_id": file_id})
    if not info.get("ok"):
        return None
    file_path = info["result"]["file_path"]
    url = f"https://api.telegram.org/file/bot{BOT_TOKEN}/{file_path}"
    tmp = tempfile.NamedTemporaryFile(suffix=".ogg", delete=False)
    urllib.request.urlretrieve(url, tmp.name)
    return tmp.name

def transcribe_audio(ogg_path):
    try:
        wav_path = ogg_path.replace(".ogg", ".wav")
        subprocess.run(["ffmpeg", "-y", "-i", ogg_path, wav_path],
                      capture_output=True, timeout=30)
        result = whisper_model.transcribe(wav_path, language="fr")
        os.unlink(ogg_path)
        os.unlink(wav_path)
        return result["text"]
    except Exception as e:
        print(f"Transcription error: {e}")
        return None

def get_offset():
    try:
        with open(OFFSET_FILE) as f:
            return int(f.read().strip())
    except:
        return 0

def save_offset(offset):
    with open(OFFSET_FILE, "w") as f:
        f.write(str(offset))

def read_file(path):
    try:
        with open(path) as f:
            return f.read()
    except:
        return ""

def write_file(path, content):
    """Ecrit le contenu dans un fichier, cree les dossiers parents si necessaire."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(content)

def try_refresh_auth():
    """Tente un refresh du token OAuth. Retourne True si OK."""
    try:
        print("Tentative refresh token...")
        result = subprocess.run(
            [REFRESH_SCRIPT],
            capture_output=True, text=True, timeout=30
        )
        print(f"Refresh: {result.stdout.strip()}")
        return result.returncode == 0
    except Exception as e:
        print(f"Refresh error: {e}")
        return False

def get_daily_note_path():
    """Retourne le chemin de la daily note du jour."""
    today = datetime.now().strftime("%Y-%m-%d")
    return f"{DAILY_DIR}/{today}.md"

def get_daily_note_content():
    """Lit la daily note du jour. Retourne le contenu ou une chaine vide."""
    return read_file(get_daily_note_path())


# ---------------------------------------------------------------------------
# Parsing des priorites dans la daily note
# ---------------------------------------------------------------------------

def parse_priorities(content):
    """
    Parse les priorites de la daily note.
    Retourne une liste de dicts : {line_start, line_end, title, done, block}
    Accepte plusieurs formats de heading :
      ## Priorite #1, ## Priorité #1, ## 1., ## Priorite 1, ## [FAIT] Priorite #1
    Le bloc s'etend jusqu'au prochain '## ' ou la fin de la section.
    """
    lines = content.split("\n")
    priorities = []
    i = 0
    while i < len(lines):
        line = lines[i]
        # Detecter une ligne de priorite (faite ou non) — flexible sur le format
        done_match = re.match(r"^## \[FAIT\]\s*(?:Priorit[eé]\s*#?)?(\d+)", line, re.IGNORECASE)
        open_match = re.match(r"^## (?:Priorit[eé]\s*#?\s*)?(\d+)[\s.\-—]", line, re.IGNORECASE)
        if done_match or open_match:
            is_done = done_match is not None
            line_start = i
            title = line
            # Collecter le bloc jusqu'au prochain ## ou fin de section
            block_lines = [line]
            j = i + 1
            while j < len(lines):
                # Arret si on rencontre un autre ## (nouvelle section ou priorite)
                if lines[j].startswith("## "):
                    break
                block_lines.append(lines[j])
                j += 1
            priorities.append({
                "line_start": line_start,
                "line_end": j - 1,
                "title": title,
                "done": is_done,
                "block": "\n".join(block_lines),
                "number": int((done_match or open_match).group(1)),
            })
            i = j
        else:
            i += 1
    return priorities

def get_first_unchecked_priority(content):
    """Retourne la premiere priorite non faite, ou None."""
    priorities = parse_priorities(content)
    for p in priorities:
        if not p["done"]:
            return p
    return None


# ---------------------------------------------------------------------------
# Commandes Chief of Staff
# ---------------------------------------------------------------------------

# Mots-cles pour chaque commande (premier mot du message, insensible a la casse)
FAIT_KEYWORDS = {"fait", "done", "ok"}
QUOI_KEYWORDS = {"quoi", "?", "priorité", "priorite", "next"}
STATUS_KEYWORDS = {"status", "score", "bilan"}
RECAP_KEYWORDS = {"recap"}
CHERCHE_PREFIXES = {"cherche", "contexte", "vault"}

# Note : "next" est partage entre "fait" et "quoi". On le met dans "quoi"
# car c'est plus naturel ("c'est quoi la suite"). Pour marquer une tache
# comme faite, Pierre utilise "fait", "done" ou "ok".


def is_chief_command(text):
    """Verifie si le texte correspond a une commande Chief of Staff."""
    word = text.strip().lower().split()[0] if text.strip() else ""
    if word in FAIT_KEYWORDS:
        return True
    if word in QUOI_KEYWORDS:
        return True
    if word in STATUS_KEYWORDS:
        return True
    if word in RECAP_KEYWORDS:
        return True
    if word in CHERCHE_PREFIXES:
        return True
    return False


# ---------------------------------------------------------------------------
# Mode Debrief — capture des reponses vocales de fin de journee
# ---------------------------------------------------------------------------

def get_open_debrief_file():
    """Retourne le chemin du fichier debrief ouvert aujourd'hui, ou None."""
    today = datetime.now().strftime("%Y-%m-%d")
    path = f"{DEBRIEF_DIR}/{today}.md"
    if not os.path.exists(path):
        return None
    try:
        with open(path) as f:
            content = f.read()
        # Lire le status dans le frontmatter
        for line in content.split("\n")[:10]:
            if line.startswith("status:"):
                status = line.split(":", 1)[1].strip()
                if status == "open":
                    return path
                return None
    except Exception:
        return None
    return None


def append_debrief_response(path, text):
    """Ajoute une reponse de Pierre au fichier debrief."""
    now = datetime.now().strftime("%H:%M")
    try:
        with open(path, "a") as f:
            f.write(f"\n### Reponse a {now}\n{text}\n")
    except Exception as exc:
        print(f"Erreur ajout reponse debrief : {exc}")


def close_debrief(path):
    """Passe le debrief de 'open' a 'closed'."""
    try:
        with open(path) as f:
            content = f.read()
        content = content.replace("status: open", "status: closed")
        now = datetime.now().strftime("%H:%M")
        content = content.replace(
            "started_at:",
            f"closed_at: {now}\nstarted_at:"
        )
        with open(path, "w") as f:
            f.write(content)
    except Exception as exc:
        print(f"Erreur cloture debrief : {exc}")


FIN_KEYWORDS = {"fin", "stop", "termine", "terminé", "ok c'est bon", "voila"}


def is_fin_command(text):
    """Detecte si le message cloture le debrief."""
    return text.strip().lower() in FIN_KEYWORDS


def handle_chief_command(text):
    """
    Traite une commande Chief of Staff.
    Retourne une chaine de reponse, ou None si ce n'est pas une commande.
    Si la commande necessite un appel Claude (fait -> recalcul), retourne
    un tuple (reponse_immediate, besoin_claude, prompt_claude).
    """
    word = text.strip().lower().split()[0] if text.strip() else ""

    if word in FAIT_KEYWORDS:
        return handle_fait()
    if word in QUOI_KEYWORDS:
        return handle_quoi()
    if word in STATUS_KEYWORDS:
        return handle_status()
    if word in RECAP_KEYWORDS:
        return handle_recap()
    if word in CHERCHE_PREFIXES:
        terme = text.strip()[len(word):].strip()
        return handle_cherche(terme)
    return None


def handle_fait():
    """
    Marque la premiere priorite non faite comme terminee.
    Met a jour la daily note, puis demande a Claude de recalculer.
    Retourne un tuple (reponse_immediate, besoin_claude, prompt_claude)
    ou juste une chaine si pas besoin de Claude.
    """
    content = get_daily_note_content()
    if not content:
        return "Le briefing du matin n'est pas encore passe. Il arrive a 8h."

    priority = get_first_unchecked_priority(content)
    if not priority:
        # Toutes les priorites sont faites
        priorities = parse_priorities(content)
        total = len(priorities)
        done_count = sum(1 for p in priorities if p["done"])
        return f"Les {done_count} priorites du jour sont faites. Score: {done_count}/{total}. Tu veux que je recalcule ?"

    # Marquer la priorite comme faite dans la daily note
    now = datetime.now().strftime("%H:%M")
    lines = content.split("\n")

    # Remplacer la ligne de titre : ## Priorite #N -> ## [FAIT] Priorite #N
    old_title = lines[priority["line_start"]]
    new_title = old_title.replace("## Priorit", "## [FAIT] Priorit", 1)
    lines[priority["line_start"]] = new_title

    # Ajouter le timestamp juste apres le bloc de la priorite
    timestamp_line = f"Complete a {now}"
    # Inserer apres la derniere ligne du bloc
    insert_pos = priority["line_end"] + 1
    lines.insert(insert_pos, timestamp_line)

    updated_content = "\n".join(lines)
    write_file(get_daily_note_path(), updated_content)

    # Extraire un titre lisible
    title_clean = re.sub(r"^## (\[FAIT\] )?", "", old_title).strip()

    # Verifier s'il reste des priorites non faites
    remaining = parse_priorities(updated_content)
    done_count = sum(1 for p in remaining if p["done"])
    total = len(remaining)
    undone = [p for p in remaining if not p["done"]]

    if not undone:
        return f"{title_clean} -- fait a {now}.\n\nLes {total} priorites du jour sont faites. Score: {done_count}/{total}. Tu veux que je recalcule ?"

    # Il reste des priorites : demander a Claude de recalculer l'ordre
    # Pour l'instant, retourner la confirmation + la prochaine priorite
    next_p = undone[0]
    next_title = re.sub(r"^## (\[FAIT\] )?", "", next_p["title"]).strip()

    response = f"{title_clean} -- fait a {now}. ({done_count}/{total})\n\nProchaine priorite :\n{next_title}"

    # Ajouter le contenu du bloc de la prochaine priorite (sans le titre)
    block_lines = next_p["block"].split("\n")[1:]
    block_text = "\n".join(l for l in block_lines if l.strip()).strip()
    if block_text:
        response += f"\n{block_text}"

    return response


def handle_quoi():
    """
    Retourne la premiere priorite non faite avec son contexte complet.
    """
    content = get_daily_note_content()
    if not content:
        return "Le briefing du matin n'est pas encore passe. Il arrive a 8h."

    priority = get_first_unchecked_priority(content)
    if not priority:
        priorities = parse_priorities(content)
        total = len(priorities)
        return f"Toutes les priorites sont faites ({total}/{total}). Tu veux que je recalcule ?"

    # Extraire un titre lisible
    title = re.sub(r"^## ", "", priority["title"]).strip()

    # Contenu complet du bloc
    block_lines = priority["block"].split("\n")[1:]
    block_text = "\n".join(l for l in block_lines if l.strip()).strip()

    priorities = parse_priorities(content)
    done_count = sum(1 for p in priorities if p["done"])
    total = len(priorities)

    response = f"({done_count}/{total}) {title}"
    if block_text:
        response += f"\n\n{block_text}"

    return response


def handle_status():
    """
    Retourne le score du jour : combien de priorites faites vs total.
    """
    content = get_daily_note_content()
    if not content:
        return "Le briefing du matin n'est pas encore passe. Il arrive a 8h."

    priorities = parse_priorities(content)
    if not priorities:
        return "Aucune priorite trouvee dans la daily note."

    done = [p for p in priorities if p["done"]]
    undone = [p for p in priorities if not p["done"]]
    total = len(priorities)
    done_count = len(done)

    # Noms des priorites faites
    done_names = []
    for p in done:
        name = re.sub(r"^## \[FAIT\] Priorit[eé] #\d+ — ", "", p["title"]).strip()
        # Fallback si le format est different
        if name == p["title"]:
            name = re.sub(r"^## \[FAIT\] ", "", p["title"]).strip()
        done_names.append(name)

    # Noms des priorites restantes
    undone_names = []
    for p in undone:
        name = re.sub(r"^## Priorit[eé] #\d+ — ", "", p["title"]).strip()
        if name == p["title"]:
            name = re.sub(r"^## ", "", p["title"]).strip()
        undone_names.append(name)

    response = f"Score: {done_count}/{total}."
    if done_names:
        response += f"\nFait: {', '.join(done_names)}."
    if undone_names:
        response += f"\nReste: {', '.join(undone_names)}."

    return response


def handle_recap():
    """
    Envoie la daily note complete sur Telegram (tronquee a 4000 chars si necessaire).
    """
    content = get_daily_note_content()
    if not content:
        return "Le briefing du matin n'est pas encore passe. Il arrive a 8h."

    today = datetime.now().strftime("%Y-%m-%d")
    header = f"Daily note {today} :\n\n"
    # send_message gere deja le decoupage en chunks de 4000
    return header + content


def handle_cherche(terme):
    """
    Recherche un terme dans le vault Obsidian avec grep.
    Retourne les 5 premiers resultats avec des extraits.
    """
    if not terme:
        return "Usage : cherche [terme]\nExemple : cherche Nicolas, cherche robot trading"

    try:
        result = subprocess.run(
            ["grep", "-r", "-i", "-l", "--include=*.md", terme, VAULT_DIR],
            capture_output=True, text=True, timeout=30
        )
        files = result.stdout.strip().split("\n") if result.stdout.strip() else []
    except subprocess.TimeoutExpired:
        return "Recherche trop longue (timeout)."
    except Exception as e:
        return f"Erreur recherche: {e}"

    if not files:
        return f"Aucun resultat pour '{terme}' dans le vault."

    # Limiter a 5 fichiers
    files = files[:5]
    response_parts = [f"Resultats pour '{terme}' ({len(files)} fichier{'s' if len(files) > 1 else ''}) :"]

    for filepath in files:
        # Nom lisible (relatif au vault)
        rel_path = filepath.replace(VAULT_DIR + "/", "")

        # Extraire les lignes contenant le terme (max 3 par fichier)
        try:
            grep_result = subprocess.run(
                ["grep", "-i", "-n", "-m", "3", terme, filepath],
                capture_output=True, text=True, timeout=10
            )
            snippets = grep_result.stdout.strip()
        except:
            snippets = ""

        response_parts.append(f"\n{rel_path}")
        if snippets:
            # Tronquer chaque ligne a 120 chars
            for line in snippets.split("\n")[:3]:
                if len(line) > 120:
                    line = line[:117] + "..."
                response_parts.append(f"  {line}")

    return "\n".join(response_parts)


# ---------------------------------------------------------------------------
# Contexte et appel Claude
# ---------------------------------------------------------------------------

def build_context(message):
    """Construit le prompt avec tout le contexte memoire"""
    today = datetime.now().strftime("%Y-%m-%d")
    log_file = f"{MEMORY_DIR}/logs/{today}.md"

    context = "Tu es le cerveau autonome de Pierre. Il te parle depuis Telegram.\n"
    context += "Reponds en francais, concis, direct. Texte brut (pas de markdown).\n"
    context += "Max 500 mots.\n\n"
    context += "=== SOUL ===\n" + read_file(f"{MEMORY_DIR}/SOUL.md") + "\n\n"
    context += "=== PRIMER ===\n" + read_file(f"{MEMORY_DIR}/primer.md") + "\n\n"
    context += "=== MEMOIRE ===\n" + read_file(f"{MEMORY_DIR}/MEMORY.md") + "\n\n"
    context += "=== LOG DU JOUR ===\n"
    log = read_file(log_file)
    if log:
        lines = log.strip().split("\n")
        context += "\n".join(lines[-30:]) + "\n\n"
    context += f"MESSAGE DE PIERRE : {message}"
    return context

def ask_claude(message, session_id=None, retry=False):
    """Envoie un message a Claude Code. Self-healing si timeout/erreur."""
    global cli_fail_count

    context = build_context(message)

    cmd = [
        "claude", "-p", context,
        "--model", "sonnet",
        "--output-format", "text",
        "--allowedTools", "Read,Edit",
        "--max-turns", "8"
    ]

    if session_id:
        cmd = [
            "claude", "-p", message,
            "--continue", session_id,
            "--model", "sonnet",
            "--output-format", "text",
            "--allowedTools", "Read,Edit,Bash",
            "--max-turns", "8"
        ]

    try:
        print(f"CMD: claude -p {'(continue '+session_id+')' if session_id else '(new)'} [{len(context)} chars]")
        result = subprocess.run(
            cmd,
            capture_output=True, text=True,
            timeout=300,
            cwd=PROJECTS_DIR
        )
        stdout = result.stdout.strip()
        stderr = result.stderr.strip()
        print(f"RC={result.returncode} STDOUT={len(stdout)} STDERR={len(stderr)}")
        if stderr:
            print(f"STDERR: {stderr[:200]}")

        # Detecter erreur d'auth dans stderr
        auth_error = any(x in stderr.lower() for x in ["authentication", "401", "unauthorized", "token"])

        if auth_error and not retry:
            print("Erreur d'auth detectee, tentative refresh...")
            if try_refresh_auth():
                return ask_claude(message, session_id=session_id, retry=True)
            else:
                cli_fail_count += 1
                return "Erreur d'authentification Claude CLI. Token refresh echoue. Pierre doit se reconnecter."

        if stdout:
            cli_fail_count = 0
            return stdout
        if stderr:
            cli_fail_count += 1
            return f"[stderr] {stderr[:3000]}"

        cli_fail_count += 1
        return f"Claude a retourne vide (code={result.returncode}). Renvoie ton message."

    except subprocess.TimeoutExpired:
        cli_fail_count += 1
        # Si timeout, tenter refresh au cas ou c'est un probleme d'auth qui hang
        if not retry and cli_fail_count >= 2:
            print(f"Timeout #{cli_fail_count}, tentative refresh...")
            if try_refresh_auth():
                return ask_claude(message, session_id=session_id, retry=True)
        if cli_fail_count >= MAX_CLI_FAILS:
            send_message("Claude CLI timeout x3. Possible probleme d'auth ou de reseau sur le VPS.")
            cli_fail_count = 0
        return "Timeout — la tache a pris plus de 5 minutes."
    except Exception as e:
        cli_fail_count += 1
        return f"Erreur: {e}"


# ---------------------------------------------------------------------------
# Boucle principale
# ---------------------------------------------------------------------------

print("Telegram bot started. Self-healing actif. Commandes Chief of Staff actives.")
offset = get_offset()

while True:
    try:
        result = api_call("getUpdates", {"offset": offset, "timeout": 30})
        if not result.get("ok") or not result.get("result"):
            continue

        for update in result["result"]:
            uid = update["update_id"]
            offset = uid + 1
            save_offset(offset)

            msg = update.get("message", {})
            chat_id = msg.get("chat", {}).get("id", 0)
            if chat_id != CHAT_ID:
                continue

            text = msg.get("text", "")

            # Vocal
            voice = msg.get("voice")
            audio = msg.get("audio")
            voice_obj = voice or audio
            if voice_obj and not text:
                send_message("Transcription...")
                ogg_file = download_file(voice_obj["file_id"])
                if ogg_file:
                    text = transcribe_audio(ogg_file)
                    if text:
                        send_message(f"[vocal] {text}")
                    else:
                        send_message("Transcription echouee.")
                        continue
                else:
                    send_message("Fichier vocal non telecharge.")
                    continue

            if not text:
                continue

            # --- Mode Debrief — si un debrief est ouvert, capture la reponse ---
            debrief_path = get_open_debrief_file()
            if debrief_path:
                if is_fin_command(text):
                    append_debrief_response(debrief_path, text)
                    close_debrief(debrief_path)
                    send_message("Debrief cloture. Le resume du jour integrera tes reponses a 21h.")
                    continue
                # Les commandes Chief of Staff rapides passent en priorite (fait, quoi, status...)
                if not is_chief_command(text):
                    # Toute autre reponse pendant le debrief est capturee
                    append_debrief_response(debrief_path, text)
                    send_message("Note. Continue, ou tape 'fin' quand tu as termine.")
                    continue
            # --- Fin mode Debrief ---

            # --- Commandes Chief of Staff (rapides, locales) ---
            if is_chief_command(text):
                print(f"[chief] {text[:80]}")
                try:
                    response = handle_chief_command(text)
                    if response:
                        send_message(response)
                except Exception as e:
                    print(f"Erreur commande Chief: {e}")
                    send_message(f"Erreur commande: {e}")
                continue
            # --- Fin Chief of Staff ---

            # --- Twitter Engine Handler ---
            if TWITTER_ENGINE_AVAILABLE and is_twitter_command(text):
                try:
                    from src.telegram_handler import handle_twitter_command
                    response = handle_twitter_command(text)
                    send_message(response)
                except Exception as e:
                    send_message(f"Erreur Twitter Engine: {e}")
                continue
            # --- Fin Twitter Engine ---

            print(f"[msg] {text[:80]}")
            send_message("...")

            response = ask_claude(text)

            print(f"Reponse ({len(response)} chars)")
            send_message(response)

    except KeyboardInterrupt:
        break
    except Exception as e:
        print(f"Error: {e}")
        time.sleep(5)
