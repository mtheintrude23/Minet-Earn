import sys
import urllib.request
import urllib.parse
import subprocess
import tempfile
import os
import time
import ssl

BU = "https://dashboard.minet.vn"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7",
}

# Bo qua SSL verify de tranh loi EOF/SSL
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE

def fetch(url, retries=3):
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=30, context=CTX) as r:
                return r.read().decode()
        except Exception as e:
            if i < retries - 1:
                print(f"Retrying... ({i+1}/{retries})")
                time.sleep(2)
            else:
                raise e

def run(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)

def restart_if_stopped():
    result = run("minet dashboard status")
    output = result.stdout + result.stderr
    print(output.strip())

    mining_stopped = "Mining: stopped" in output
    tunnel_stopped = "Tunnel: stopped" in output

    if mining_stopped or tunnel_stopped:
        print("Detected stopped service, restarting...")
        run("minet dashboard stop")
        time.sleep(2)
        run("minet dashboard start")
        print("Restarted.")
    else:
        print("All services running OK.")

def watch_loop():
    print("Watching services every 60s (Ctrl+C to stop)...")
    while True:
        try:
            time.sleep(60)
            restart_if_stopped()
        except KeyboardInterrupt:
            print("\nStopped watching.")
            break

# ─── Setup ────────────────────────────────────────────────────────────────────

print()
print("===== Minet Mining Setup =====")
print()

EM = ""
if not EM:
    try:
        tty = open("/dev/tty", "r+")
        tty.write("Email: ")
        tty.flush()
        EM = tty.readline().strip()
        tty.close()
    except Exception:
        pass

if not EM:
    try:
        sys.stdin = open("/dev/tty")
        sys.stdout.write("Email: ")
        sys.stdout.flush()
        EM = sys.stdin.readline().strip()
    except Exception:
        pass

if not EM:
    try:
        EM = input("Email: ").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        sys.exit(1)

if not EM:
    print("Email required.")
    sys.exit(1)

print("Preparing...")

EE = urllib.parse.quote(EM, safe="")

try:
    CI = fetch("https://api.ipify.org").strip()
except Exception:
    print("Network error.")
    sys.exit(1)

EI = urllib.parse.quote(CI, safe="")

setup_url = f"{BU}/api/minecoin/setup?email={EE}&ip={EI}&mode=dashboard"

try:
    script = fetch(setup_url)
except Exception as e:
    print(f"Failed to fetch setup script: {e}")
    sys.exit(1)

with tempfile.NamedTemporaryFile(mode="w", suffix=".sh", delete=False) as f:
    f.write(script)
    tmp = f.name

try:
    os.chmod(tmp, 0o755)
    result = subprocess.run(["sh", tmp], check=False)
finally:
    os.unlink(tmp)

if result.returncode != 0:
    sys.exit(result.returncode)

# ─── Auto start + watch ───────────────────────────────────────────────────────

print()
print("Starting mining...")
subprocess.run(["minet", "dashboard", "start"], check=False)
time.sleep(3)

restart_if_stopped()
watch_loop()
