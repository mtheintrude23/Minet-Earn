import sys
import urllib.request
import urllib.parse
import subprocess
import tempfile
import os

BU = "https://dashboard.minet.vn"

print()
print("===== Minet Mining Setup =====")
print()

# Doc tu /dev/tty de hoat dong khi chay qua curl | python3
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

# URL encode email
EE = urllib.parse.quote(EM, safe="")

# Lay IP cong khai
try:
    with urllib.request.urlopen("https://api.ipify.org", timeout=10) as r:
        CI = r.read().decode().strip()
except Exception:
    print("Network error.")
    sys.exit(1)

if not CI:
    print("Network error.")
    sys.exit(1)

# URL encode IP
EI = urllib.parse.quote(CI, safe="")

# Tai script tu server
setup_url = f"{BU}/api/minecoin/setup?email={EE}&ip={EI}&mode=dashboard"

try:
    with urllib.request.urlopen(setup_url, timeout=30) as r:
        script = r.read().decode()
except Exception as e:
    print(f"Failed to fetch setup script: {e}")
    sys.exit(1)

# Chay script bang sh
with tempfile.NamedTemporaryFile(mode="w", suffix=".sh", delete=False) as f:
    f.write(script)
    tmp = f.name

try:
    os.chmod(tmp, 0o755)
    result = subprocess.run(["sh", tmp], check=False)
    sys.exit(result.returncode)
finally:
    os.unlink(tmp)
