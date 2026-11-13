#!/usr/bin/env bash
# Provision a freshly applied tokyo-dev instance and generate the client configs.
#
# Run after `terraform apply`:
#   ./scripts/setup.sh                   # sing-box (SFM) only
#   ./scripts/setup.sh --with-wireguard  # also set up WireGuard (optional)
#
# What it does (safe to re-run; existing server keys/configs are reused):
#   1. read the new public IP from Terraform and update the `Host tokyo-dev` block in ~/.ssh/config
#   2. wait for SSH, then install sing-box (and WireGuard with --with-wireguard) and write the server configs
#   3. write ~/wg/sfm-profile.json (SFM profile), plus ~/wg/tokyo.conf (WireGuard client) with --with-wireguard
#
# Override with environment variables when needed:
#   SSH_KEY, SSH_HOST_ALIAS, SSH_CONFIG, KNOWN_HOSTS, WG_DIR

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/lightsail-iac_dev}"
SSH_HOST_ALIAS="${SSH_HOST_ALIAS:-tokyo-dev}"
SSH_CONFIG="${SSH_CONFIG:-$HOME/.ssh/config}"
KNOWN_HOSTS="${KNOWN_HOSTS:-$HOME/.ssh/known_hosts}"
WG_DIR="${WG_DIR:-$HOME/wg}"
SSH_USER="ubuntu"
IS_WIREGUARD_ENABLED=0
SSH_MAX_TRIES=30

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required. $2"
}

get_public_ip() {
  local ip
  ip="$(terraform -chdir="$REPO_DIR" output -raw public_ip 2>/dev/null)" || ip=""
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "cannot read public_ip from Terraform (got '${ip}'). Run terraform apply first."
  printf '%s' "$ip"
}

update_ssh_config() {
  local ip="$1"
  mkdir -p "$(dirname "$SSH_CONFIG")"
  touch "$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"

  if ! grep -q "^Host ${SSH_HOST_ALIAS}\$" "$SSH_CONFIG"; then
    log "adding Host ${SSH_HOST_ALIAS} to ${SSH_CONFIG}"
    {
      printf '\nHost %s\n' "$SSH_HOST_ALIAS"
      printf '  HostName %s\n' "$ip"
      printf '  User %s\n' "$SSH_USER"
      printf '  IdentityFile %s\n' "$SSH_KEY"
      printf '  IdentitiesOnly yes\n'
    } >>"$SSH_CONFIG"
    return
  fi

  log "updating HostName of Host ${SSH_HOST_ALIAS} in ${SSH_CONFIG} (backup: ${SSH_CONFIG}.bak)"
  cp "$SSH_CONFIG" "${SSH_CONFIG}.bak"
  awk -v alias="$SSH_HOST_ALIAS" -v ip="$ip" '
    /^Host[[:space:]]/ { is_target = ($2 == alias) }
    is_target && /^[[:space:]]*HostName[[:space:]]/ { sub(/HostName[[:space:]].*/, "HostName " ip) }
    { print }
  ' "${SSH_CONFIG}.bak" >"$SSH_CONFIG"
}

wait_for_ssh() {
  local ip="$1" i
  mkdir -p "$(dirname "$KNOWN_HOSTS")"
  touch "$KNOWN_HOSTS"
  # A reused IP would otherwise trigger "REMOTE HOST IDENTIFICATION HAS CHANGED".
  ssh-keygen -R "$ip" -f "$KNOWN_HOSTS" >/dev/null 2>&1 || true

  for ((i = 1; i <= SSH_MAX_TRIES; i++)); do
    if ssh_run "$ip" true 2>/dev/null; then
      return 0
    fi
    log "waiting for SSH (${i}/${SSH_MAX_TRIES})..."
    sleep 10
  done
  die "SSH is not reachable. Check that your public IP is still listed in ssh_allowed_cidrs."
}

ssh_run() {
  local ip="$1"
  shift
  ssh -i "$SSH_KEY" \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$KNOWN_HOSTS" \
    -o ConnectTimeout=5 \
    "${SSH_USER}@${ip}" "$@"
}

ensure_mac_wireguard_keys() {
  mkdir -p "$WG_DIR"
  chmod 700 "$WG_DIR"
  if [[ ! -s "$WG_DIR/mac.key" ]]; then
    log "generating Mac WireGuard keys in ${WG_DIR}"
    (umask 077; wg genkey | tee "$WG_DIR/mac.key" | wg pubkey >"$WG_DIR/mac.pub")
  fi
  [[ -s "$WG_DIR/mac.pub" ]] || (umask 077; wg pubkey <"$WG_DIR/mac.key" >"$WG_DIR/mac.pub")
}

# Runs on the server as root. Idempotent: existing keys and configs are kept.
# Progress goes to stderr; the machine-readable result goes to fd 3 (captured by the caller).
# MAC_PUB is empty unless WireGuard is enabled.
provision_server() {
  local ip="$1" mac_pub="$2"
  ssh_run "$ip" "sudo MAC_PUB='${mac_pub}' bash -s" <<'REMOTE'
set -euo pipefail
exec 3>&1 1>&2
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y tcpdump mtr-tiny dnsutils curl python3

if ! command -v sing-box >/dev/null 2>&1; then
  curl -fsSL https://sing-box.app/install.sh | sh
fi

# --- sing-box (Shadowsocks 2022) --------------------------------------------
install -d /etc/sing-box
SB_CHANGED=0
if [ ! -s /etc/sing-box/config.json ]; then
  NEW_PASSWORD="$(sing-box generate rand --base64 16)"
  cat > /etc/sing-box/config.json <<SBCONF
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": 8388,
      "method": "2022-blake3-aes-128-gcm",
      "password": "${NEW_PASSWORD}"
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ]
}
SBCONF
  SB_CHANGED=1
fi

sing-box check -c /etc/sing-box/config.json
systemctl enable sing-box
if [ "$SB_CHANGED" = 1 ]; then systemctl restart sing-box; else systemctl start sing-box; fi

SS_PASSWORD="$(python3 -c 'import json; d = json.load(open("/etc/sing-box/config.json")); print([i["password"] for i in d["inbounds"] if i["type"] == "shadowsocks"][0])')"
printf 'SS_PASSWORD=%s\n' "$SS_PASSWORD" >&3

# --- WireGuard (optional) ---------------------------------------------------
[ -n "${MAC_PUB:-}" ] || exit 0

apt-get install -y wireguard
if ! modprobe wireguard; then
  echo "WireGuard kernel module is unavailable. Run 'sudo apt-get upgrade -y && sudo reboot', then re-run this script." >&2
  exit 1
fi

install -d -m 700 /etc/wireguard
if [ ! -s /etc/wireguard/server.key ]; then
  (umask 077; wg genkey > /etc/wireguard/server.key)
fi
(umask 077; wg pubkey < /etc/wireguard/server.key > /etc/wireguard/server.pub)

NIC="$(ip -o -4 route show to default | awk '{print $5; exit}')"
[ -n "$NIC" ] || { echo "cannot detect the default network interface" >&2; exit 1; }

WG_CHANGED=0
if [ ! -f /etc/wireguard/wg0.conf ] || ! grep -q "PublicKey = ${MAC_PUB}" /etc/wireguard/wg0.conf; then
  (
    umask 077
    cat > /etc/wireguard/wg0.conf <<WGCONF
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $(cat /etc/wireguard/server.key)
PostUp   = iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o ${NIC} -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o ${NIC} -j MASQUERADE

[Peer]
PublicKey = ${MAC_PUB}
AllowedIPs = 10.8.0.2/32
WGCONF
  )
  WG_CHANGED=1
fi

echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-wg.conf
sysctl -p /etc/sysctl.d/99-wg.conf
systemctl enable wg-quick@wg0
if [ "$WG_CHANGED" = 1 ]; then systemctl restart wg-quick@wg0; else systemctl start wg-quick@wg0; fi

printf 'SERVER_PUB=%s\n' "$(cat /etc/wireguard/server.pub)" >&3
REMOTE
}

extract_value() {
  local key="$1" text="$2" value
  value="$(printf '%s\n' "$text" | sed -n "s/^${key}=//p" | head -n 1)"
  [[ -n "$value" ]] || die "server did not return ${key}"
  printf '%s' "$value"
}

backup_if_exists() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  cp -p "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
}

write_wireguard_client_config() {
  local ip="$1" server_pub="$2" out="$WG_DIR/tokyo.conf"
  backup_if_exists "$out"
  (
    umask 077
    cat >"$out" <<EOF
[Interface]
Address = 10.8.0.2/24
PrivateKey = $(cat "$WG_DIR/mac.key")

[Peer]
PublicKey = ${server_pub}
Endpoint = ${ip}:51820
AllowedIPs = 10.8.0.0/24
PersistentKeepalive = 25
EOF
  )
  log "wrote $out"
}

write_sfm_profile() {
  local ip="$1" ss_password="$2"
  local template="$REPO_DIR/scripts/sfm-profile.json.tmpl" out="$WG_DIR/sfm-profile.json"
  [[ -f "$template" ]] || die "missing template: $template"
  backup_if_exists "$out"
  (
    umask 077
    # base64 never contains '|', so it is a safe sed delimiter.
    sed -e "s|__PUBLIC_IP__|${ip}|g" -e "s|__SS_PASSWORD__|${ss_password}|g" "$template" >"$out"
  )
  python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$out" \
    || die "generated SFM profile is not valid JSON: $out"
  log "wrote $out"
}

usage() {
  cat <<EOF
Usage: ${0##*/} [--with-wireguard]

  --with-wireguard   also set up WireGuard on the server and write ${WG_DIR}/tokyo.conf
  -h, --help         show this help
EOF
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --with-wireguard) IS_WIREGUARD_ENABLED=1 ;;
      -h | --help) usage; exit 0 ;;
      *) usage >&2; die "unknown option: $1" ;;
    esac
    shift
  done
}

print_next_steps() {
  {
    printf '\nDone. Next:\n'
    printf '  SFM       : import %s/sfm-profile.json (or paste its content) and start it\n' "$WG_DIR"
    printf '  SSH       : ssh %s\n' "$SSH_HOST_ALIAS"
    if ((IS_WIREGUARD_ENABLED)); then
      printf '  WireGuard : sudo wg-quick up %s/tokyo.conf && ping -c 3 10.8.0.1\n' "$WG_DIR"
      printf 'Stop WireGuard before starting SFM; they both change the routing table.\n'
    fi
  } >&2
}

main() {
  parse_args "$@"

  require_command terraform "Install it first."
  require_command python3 "Install Python 3."
  if ((IS_WIREGUARD_ENABLED)); then
    require_command wg "Run: brew install wireguard-tools"
  fi
  [[ -f "$SSH_KEY" ]] || die "SSH key not found: $SSH_KEY"

  local ip mac_pub="" result server_pub ss_password
  ip="$(get_public_ip)"
  log "public IP: $ip"

  update_ssh_config "$ip"
  wait_for_ssh "$ip"

  mkdir -p "$WG_DIR"
  chmod 700 "$WG_DIR"
  if ((IS_WIREGUARD_ENABLED)); then
    ensure_mac_wireguard_keys
    mac_pub="$(cat "$WG_DIR/mac.pub")"
  fi

  log "provisioning the server (this takes a few minutes on a fresh instance)"
  result="$(provision_server "$ip" "$mac_pub")"
  ss_password="$(extract_value SS_PASSWORD "$result")"
  write_sfm_profile "$ip" "$ss_password"

  if ((IS_WIREGUARD_ENABLED)); then
    server_pub="$(extract_value SERVER_PUB "$result")"
    write_wireguard_client_config "$ip" "$server_pub"
  fi

  print_next_steps
}

main "$@"
