import sys
import urllib.request
import urllib.parse
import subprocess
import tempfile
import os

BU = "https://dashboard.minet.vn"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7",
}

print()
print("===== Minet Mining Setup =====")
print()

try:
    with open("/dev/tty") as tty:
        sys.stdout.write("Email: ")
        sys.stdout.flush()
        EM = tty.readline().strip()
except Exception:
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
    req = urllib.request.Request("https://api.ipify.org", headers=HEADERS)
    with urllib.request.urlopen(req, timeout=10) as r:
        CI = r.read().decode().strip()
except Exception:
    print("Network error.")
    sys.exit(1)

if not CI:
    print("Network error.")
    sys.exit(1)

EI = urllib.parse.quote(CI, safe="")

setup_url = f"{BU}/api/minecoin/setup?email={EE}&ip={EI}&mode=dashboard"

try:
    req = urllib.request.Request(setup_url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=30) as r:
        script = r.read().decode()
except Exception as e:
    print(f"Failed to fetch setup script: {e}")
    sys.exit(1)

# Chay setup script
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

# Tu dong start mining sau khi setup xong
print()
print("Starting mining...")
subprocess.run(["minet", "dashboard", "start"], check=False)
