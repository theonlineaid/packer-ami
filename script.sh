#!/bin/bash
# ============================================================
#  Nginx Setup Script for Ubuntu - Instance Info Page
#  Compatible with: Ubuntu 20.04 / 22.04 / 24.04
# ============================================================

set -e  # Exit immediately on error

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()    { echo -e "${GREEN}[✔]${NC} $1"; }
info()   { echo -e "${CYAN}[i]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[✘]${NC} $1"; exit 1; }

# ---------- Require root ----------
if [[ $EUID -ne 0 ]]; then
  error "Please run as root: sudo bash $0"
fi

# ============================================================
# 1. GATHER INSTANCE INFORMATION
# ============================================================
info "Collecting instance information..."

HOSTNAME=$(hostname)
OS_NAME=$(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')
KERNEL=$(uname -r)
ARCH=$(uname -m)
UPTIME=$(uptime -p 2>/dev/null || uptime)
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
CPU_CORES=$(nproc)
TOTAL_RAM=$(free -h | awk '/^Mem:/ {print $2}')
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')

# Private IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')

# Public IP (try multiple sources)
PUBLIC_IP=$(curl -sf --max-time 5 https://checkip.amazonaws.com \
         || curl -sf --max-time 5 https://api.ipify.org \
         || curl -sf --max-time 5 https://ifconfig.me \
         || echo "Unavailable")

# Instance ID (AWS EC2 / compatible)
INSTANCE_ID=$(curl -sf --max-time 3 http://169.254.169.254/latest/meta-data/instance-id \
           || curl -sf --max-time 3 -H "X-aws-ec2-metadata-token: $(curl -sf --max-time 3 -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')" http://169.254.169.254/latest/meta-data/instance-id \
           || cat /etc/machine-id 2>/dev/null | head -c 19 \
           || echo "N/A (not on cloud)")

# Availability Zone / Region (AWS)
AZ=$(curl -sf --max-time 3 http://169.254.169.254/latest/meta-data/placement/availability-zone || echo "N/A")
REGION=$(echo "$AZ" | sed 's/[a-z]$//' 2>/dev/null || echo "N/A")

# Instance Type (AWS)
INSTANCE_TYPE=$(curl -sf --max-time 3 http://169.254.169.254/latest/meta-data/instance-type || echo "N/A")

# AMI ID (AWS)
AMI_ID=$(curl -sf --max-time 3 http://169.254.169.254/latest/meta-data/ami-id || echo "N/A")

CURRENT_DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')

log "Instance information collected."

# ============================================================
# 2. INSTALL NGINX
# ============================================================
info "Updating package list..."
apt-get update -qq

info "Installing Nginx..."
apt-get install -y nginx curl > /dev/null
log "Nginx installed."

# ============================================================
# 3. CREATE HTML PAGE
# ============================================================
HTML_DIR="/var/www/html"
HTML_FILE="$HTML_DIR/index.html"

info "Writing instance info HTML page..."

cat > "$HTML_FILE" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Instance Info — ${HOSTNAME}</title>
  <link href="https://fonts.googleapis.com/css2?family=Share+Tech+Mono&family=Syne:wght@400;700;800&display=swap" rel="stylesheet" />
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    :root {
      --bg:       #0a0e17;
      --surface:  #111827;
      --border:   #1e2d40;
      --accent:   #00e5ff;
      --accent2:  #7b61ff;
      --green:    #00ff87;
      --warn:     #ffb830;
      --text:     #c9d8e8;
      --muted:    #4a6080;
      --font-mono: 'Share Tech Mono', monospace;
      --font-ui:   'Syne', sans-serif;
    }

    body {
      background: var(--bg);
      color: var(--text);
      font-family: var(--font-ui);
      min-height: 100vh;
      padding: 2rem 1rem 4rem;
      background-image:
        radial-gradient(ellipse 80% 50% at 50% -20%, rgba(0,229,255,.07), transparent),
        repeating-linear-gradient(0deg, transparent, transparent 39px, rgba(0,229,255,.03) 40px),
        repeating-linear-gradient(90deg, transparent, transparent 39px, rgba(0,229,255,.03) 40px);
    }

    header {
      text-align: center;
      margin-bottom: 3rem;
      animation: fadeDown .6s ease both;
    }
    header .label {
      font-family: var(--font-mono);
      font-size: .75rem;
      letter-spacing: .25em;
      color: var(--accent);
      text-transform: uppercase;
      margin-bottom: .5rem;
    }
    header h1 {
      font-size: clamp(1.8rem, 5vw, 3rem);
      font-weight: 800;
      color: #fff;
      letter-spacing: -.02em;
    }
    header h1 span { color: var(--accent); }
    header .meta {
      font-family: var(--font-mono);
      font-size: .8rem;
      color: var(--muted);
      margin-top: .5rem;
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
      gap: 1.25rem;
      max-width: 1100px;
      margin: 0 auto;
    }

    .card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 1.5rem;
      position: relative;
      overflow: hidden;
      animation: fadeUp .5s ease both;
    }
    .card::before {
      content: '';
      position: absolute;
      top: 0; left: 0; right: 0;
      height: 2px;
      background: linear-gradient(90deg, var(--accent), var(--accent2));
    }
    .card.wide { grid-column: 1 / -1; }
    .card-title {
      font-size: .7rem;
      letter-spacing: .2em;
      text-transform: uppercase;
      color: var(--muted);
      font-family: var(--font-mono);
      margin-bottom: 1rem;
    }

    .big-id {
      font-family: var(--font-mono);
      font-size: clamp(1.1rem, 3vw, 1.6rem);
      color: var(--accent);
      word-break: break-all;
      text-shadow: 0 0 20px rgba(0,229,255,.4);
    }

    table { width: 100%; border-collapse: collapse; }
    tr { border-bottom: 1px solid var(--border); }
    tr:last-child { border-bottom: none; }
    td {
      padding: .6rem 0;
      font-size: .9rem;
    }
    td:first-child {
      color: var(--muted);
      font-family: var(--font-mono);
      font-size: .8rem;
      width: 45%;
    }
    td:last-child {
      color: var(--text);
      font-family: var(--font-mono);
      word-break: break-word;
    }
    td .pill {
      display: inline-block;
      padding: .1rem .6rem;
      border-radius: 999px;
      font-size: .75rem;
    }
    .pill-green { background: rgba(0,255,135,.1); color: var(--green); border: 1px solid rgba(0,255,135,.3); }
    .pill-blue  { background: rgba(0,229,255,.1); color: var(--accent); border: 1px solid rgba(0,229,255,.3); }
    .pill-warn  { background: rgba(255,184,48,.1); color: var(--warn);  border: 1px solid rgba(255,184,48,.3); }

    .disk-bar-wrap { margin-top: .5rem; }
    .disk-bar-bg {
      height: 6px; border-radius: 3px;
      background: var(--border); overflow: hidden;
    }
    .disk-bar-fill {
      height: 100%; border-radius: 3px;
      background: linear-gradient(90deg, var(--accent), var(--accent2));
      width: 0;
      transition: width 1s ease;
    }
    .disk-bar-label {
      display: flex; justify-content: space-between;
      font-family: var(--font-mono); font-size: .75rem;
      color: var(--muted); margin-top: .3rem;
    }

    footer {
      text-align: center;
      font-family: var(--font-mono);
      font-size: .75rem;
      color: var(--muted);
      margin-top: 3rem;
    }

    @keyframes fadeDown {
      from { opacity:0; transform:translateY(-20px); }
      to   { opacity:1; transform:translateY(0); }
    }
    @keyframes fadeUp {
      from { opacity:0; transform:translateY(20px); }
      to   { opacity:1; transform:translateY(0); }
    }
    .card:nth-child(1){ animation-delay:.05s }
    .card:nth-child(2){ animation-delay:.10s }
    .card:nth-child(3){ animation-delay:.15s }
    .card:nth-child(4){ animation-delay:.20s }
    .card:nth-child(5){ animation-delay:.25s }
    .card:nth-child(6){ animation-delay:.30s }
  </style>
</head>
<body>

<header>
  <div class="label">Ubuntu Server</div>
  <h1>Instance <span>Dashboard</span></h1>
  <div class="meta">Generated: ${CURRENT_DATE}</div>
</header>

<div class="grid">

  <!-- Instance ID -->
  <div class="card wide">
    <div class="card-title">Instance ID</div>
    <div class="big-id">${INSTANCE_ID}</div>
  </div>

  <!-- Identity -->
  <div class="card">
    <div class="card-title">Identity</div>
    <table>
      <tr><td>Hostname</td><td>${HOSTNAME}</td></tr>
      <tr><td>OS</td><td>${OS_NAME}</td></tr>
      <tr><td>Kernel</td><td>${KERNEL}</td></tr>
      <tr><td>Architecture</td><td>${ARCH}</td></tr>
      <tr><td>Uptime</td><td>${UPTIME}</td></tr>
      <tr><td>Status</td><td><span class="pill pill-green">● Running</span></td></tr>
    </table>
  </div>

  <!-- Network -->
  <div class="card">
    <div class="card-title">Network</div>
    <table>
      <tr><td>Private IP</td><td><span class="pill pill-blue">${PRIVATE_IP}</span></td></tr>
      <tr><td>Public IP</td><td><span class="pill pill-warn">${PUBLIC_IP}</span></td></tr>
      <tr><td>Region</td><td>${REGION}</td></tr>
      <tr><td>Avail. Zone</td><td>${AZ}</td></tr>
    </table>
  </div>

  <!-- Compute -->
  <div class="card">
    <div class="card-title">Compute</div>
    <table>
      <tr><td>Instance Type</td><td>${INSTANCE_TYPE}</td></tr>
      <tr><td>AMI ID</td><td>${AMI_ID}</td></tr>
      <tr><td>CPU Model</td><td>${CPU_MODEL}</td></tr>
      <tr><td>CPU Cores</td><td>${CPU_CORES}</td></tr>
      <tr><td>Total RAM</td><td>${TOTAL_RAM}</td></tr>
    </table>
  </div>

  <!-- Storage -->
  <div class="card">
    <div class="card-title">Storage ( / )</div>
    <table>
      <tr><td>Total</td><td>${DISK_TOTAL}</td></tr>
      <tr><td>Used</td><td>${DISK_USED}</td></tr>
      <tr><td>Available</td><td>${DISK_AVAIL}</td></tr>
    </table>
    <div class="disk-bar-wrap">
      <div class="disk-bar-bg"><div class="disk-bar-fill" id="diskBar"></div></div>
      <div class="disk-bar-label"><span>Used</span><span id="diskPct">—</span></div>
    </div>
  </div>

  <!-- Nginx -->
  <div class="card">
    <div class="card-title">Web Server</div>
    <table>
      <tr><td>Server</td><td>Nginx</td></tr>
      <tr><td>Status</td><td><span class="pill pill-green">● Active</span></td></tr>
      <tr><td>Config</td><td>/etc/nginx/nginx.conf</td></tr>
      <tr><td>Root</td><td>/var/www/html</td></tr>
      <tr><td>Port</td><td>80 (HTTP)</td></tr>
    </table>
  </div>

</div>

<footer>Served by Nginx on Ubuntu &nbsp;·&nbsp; ${HOSTNAME}</footer>

<script>
  // Disk usage bar
  const used  = parseFloat("${DISK_USED}");
  const total = parseFloat("${DISK_TOTAL}");
  if (!isNaN(used) && !isNaN(total) && total > 0) {
    const pct = Math.round(used / total * 100);
    document.getElementById('diskBar').style.width = pct + '%';
    document.getElementById('diskPct').textContent  = pct + '%';
  }
</script>
</body>
</html>
HTMLEOF

log "HTML page written to $HTML_FILE"

# ============================================================
# 4. CONFIGURE NGINX
# ============================================================
NGINX_CONF="/etc/nginx/sites-available/instance-info"

info "Writing Nginx server block..."
cat > "$NGINX_CONF" << 'NGINXEOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html;

    server_name _;

    # Security headers
    add_header X-Frame-Options       "SAMEORIGIN"  always;
    add_header X-Content-Type-Options "nosniff"     always;
    add_header X-XSS-Protection       "1; mode=block" always;
    add_header Referrer-Policy        "no-referrer" always;

    # Gzip
    gzip on;
    gzip_types text/html text/css application/javascript;

    location / {
        try_files $uri $uri/ =404;
    }

    # Block hidden files
    location ~ /\. {
        deny all;
    }

    # Custom error pages (optional)
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
NGINXEOF

# Enable site
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/instance-info
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Test & reload
nginx -t && systemctl reload nginx

log "Nginx configured and reloaded."

# ============================================================
# 5. OPEN FIREWALL (UFW)
# ============================================================
if command -v ufw &>/dev/null; then
  info "Allowing HTTP (port 80) through UFW..."
  ufw allow 'Nginx HTTP' > /dev/null 2>&1 || ufw allow 80/tcp > /dev/null 2>&1
  log "Firewall rule added."
fi

# ============================================================
# 6. SUMMARY
# ============================================================
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✔  Setup Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "  Instance ID : ${CYAN}${INSTANCE_ID}${NC}"
echo -e "  Hostname    : ${CYAN}${HOSTNAME}${NC}"
echo -e "  Private IP  : ${CYAN}${PRIVATE_IP}${NC}"
echo -e "  Public IP   : ${CYAN}${PUBLIC_IP}${NC}"
echo -e "  HTML File   : ${CYAN}${HTML_FILE}${NC}"
echo -e "  Nginx Conf  : ${CYAN}${NGINX_CONF}${NC}"
echo ""
echo -e "  ${YELLOW}Open in browser:${NC}  http://${PUBLIC_IP}"
echo -e "  ${YELLOW}Or locally:${NC}       http://localhost"
echo -e "${GREEN}════════════════════════════════════════${NC}"