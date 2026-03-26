#!/usr/bin/env python3
"""
Telegram bot qui pilote Claude Code avec une session persistante.
Utilise claude -p --continue pour maintenir le contexte entre messages.
"""
import json, subprocess, time, os, urllib.request, urllib.parse, tempfile, re
from datetime import datetime

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "YOUR_BOT_TOKEN")
CHAT_ID = int(os.environ.get("TELEGRAM_CHAT_ID", "0"))
API = f"https://api.telegram.org/bot{BOT_TOKEN}"
MEMORY_DIR = "/root/claude-memory"
OFFSET_FILE = "/root/claude-heartbeat/telegram-offset"
PROJECTS_DIR = "/root/projects"
SESSION_FILE = "/root/claude-heartbeat/telegram-session-id"

# Whisper
import whisper
print("Loading Whisper...")
whisper_model = whisper.load_model("base")
print("Whisper ready.")

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

def ask_claude(message, session_id=None):
    """Envoie un message a Claude Code. Chaque message est independant avec contexte complet."""

    context = build_context(message)

    cmd = [
        "claude", "-p", context,
        "--output-format", "text",
        "--allowedTools", "Read,Edit",
        "--max-turns", "8"
    ]

    # Si on a un session_id, continuer la conversation
    if session_id:
        cmd = [
            "claude", "-p", message,
            "--continue", session_id,
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

        if stdout:
            return stdout
        if stderr:
            return f"[stderr] {stderr[:3000]}"
        return f"Claude a retourne vide (code={result.returncode}). Renvoie ton message."
    except subprocess.TimeoutExpired:
        return "Timeout — la tache a pris plus de 5 minutes."
    except Exception as e:
        return f"Erreur: {e}"

# Track si on a deja une session
has_session = False

print("Telegram bot started. Session persistante via --continue.")
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

            # Commande /restart — nouvelle session
            if text.strip().lower() == "/restart":
                has_session = False
                send_message("Session reinitialise. Prochain message = nouvelle session.")
                continue

            print(f"[{'continue' if has_session else 'new'}] {text[:80]}")
            send_message("...")

            response = ask_claude(text, is_new_session=not has_session)
            has_session = True

            print(f"Reponse ({len(response)} chars)")
            send_message(response)

    except KeyboardInterrupt:
        break
    except Exception as e:
        print(f"Error: {e}")
        time.sleep(5)
