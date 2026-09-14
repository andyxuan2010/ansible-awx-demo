#!/usr/bin/env bash
set -euo pipefail

# Discover an IPv4 network with Nmap and generate a supplemental Ansible
# inventory. The generated file is separate from hosts.yml so hand-maintained
# inventory data is never overwritten.

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
NETWORK=""
OUTPUT="$REPO_ROOT/inventory/discovery/discovered_hosts.yml"
PORTS="22,80,443,139,445,2049,2222,2223,3389,5985,8080,8443"
ATTACH_GROUP=""
SCAN_DIR=""
INPUT_XML=""
NO_OS=0

usage() {
  cat <<'USAGE'
Usage:
  scan_inventory.sh --network CIDR [options]
  scan_inventory.sh --input-xml FILE [options]

Options:
  -n, --network CIDR       IPv4 network to scan, for example 192.0.2.0/24
  -p, --ports LIST         TCP ports to scan, comma-separated
  -o, --output FILE        Generated inventory path
      --attach-group NAME  Also add discovered hosts to an existing group
      --scan-dir DIR       Save raw Nmap XML reports in DIR
      --input-xml FILE     Reuse an existing Nmap XML report for testing
      --no-os              Skip OS detection, even when running as root
  -h, --help               Show this help

Examples:
  sudo ./scripts/scan_inventory.sh --network 192.0.2.0/24
  sudo ./scripts/scan_inventory.sh --network 192.0.2.0/24 \
    --ports 22,80,443,2049 --attach-group site_d
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf 'INFO: %s\n' "$*" >&2
}

while (($# > 0)); do
  case "$1" in
    -n|--network)
      (($# >= 2)) || die "$1 requires a value"
      NETWORK="$2"
      shift 2
      ;;
    -p|--ports)
      (($# >= 2)) || die "$1 requires a value"
      PORTS="$2"
      shift 2
      ;;
    -o|--output)
      (($# >= 2)) || die "$1 requires a value"
      OUTPUT="$2"
      shift 2
      ;;
    --attach-group)
      (($# >= 2)) || die "$1 requires a value"
      ATTACH_GROUP="$2"
      shift 2
      ;;
    --scan-dir)
      (($# >= 2)) || die "$1 requires a value"
      SCAN_DIR="$2"
      shift 2
      ;;
    --input-xml)
      (($# >= 2)) || die "$1 requires a value"
      INPUT_XML="$2"
      shift 2
      ;;
    --no-os)
      NO_OS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
done

if [[ -n "$INPUT_XML" ]]; then
  [[ -f "$INPUT_XML" ]] || die "Nmap XML file not found: $INPUT_XML"
  [[ -n "$NETWORK" ]] || NETWORK="from:$INPUT_XML"
else
  [[ -n "$NETWORK" ]] || { usage >&2; die "--network is required"; }
  command -v nmap >/dev/null 2>&1 || die "nmap is required; install it with your Linux package manager"
fi

if [[ -n "$ATTACH_GROUP" ]]; then
  [[ "$ATTACH_GROUP" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
    die "--attach-group must contain only letters, numbers, and underscores"
  [[ "$ATTACH_GROUP" != discovered ]] || die "--attach-group cannot be discovered"
fi

command -v awk >/dev/null 2>&1 || die "awk is required"
command -v sed >/dev/null 2>&1 || die "sed is required"
command -v sort >/dev/null 2>&1 || die "sort is required"
command -v mktemp >/dev/null 2>&1 || die "mktemp is required"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ansible-inventory-scan.XXXXXX")"
cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT

DISCOVERY_XML="$WORK_DIR/discovery.xml"
DETAIL_XML="$WORK_DIR/details.xml"
DISCOVERY_DATA="$WORK_DIR/discovery.data"
DETAIL_DATA="$WORK_DIR/details.data"
MERGED_DATA="$WORK_DIR/merged.data"
TARGETS_FILE="$WORK_DIR/targets.txt"

extract_ips() {
  local xml_file="$1"
  sed 's/></>\n</g' "$xml_file" | awk '
    function attr(line, key,    p, rest, end) {
      p = index(line, key "=\"")
      if (!p) return ""
      rest = substr(line, p + length(key) + 2)
      end = index(rest, "\"")
      if (!end) return ""
      return substr(rest, 1, end - 1)
    }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line ~ /^<host[ >]/) {
        inhost = 1
        is_up = 0
        ip = ""
      }
      if (!inhost) next
      if (line ~ /^<status / && attr(line, "state") == "up") is_up = 1
      if (line ~ /^<address / && line ~ /addrtype="ipv4"/) ip = attr(line, "addr")
      if (line ~ /^<\/host>/) {
        if (is_up && ip != "") print ip
        inhost = 0
      }
    }
  '
}

# Emit: ip|reverse_dns|mac|open_ports|services|os_match
parse_xml() {
  local xml_file="$1"
  local mode="$2"
  sed 's/></>\n</g' "$xml_file" | awk -v mode="$mode" '
    function attr(line, key,    p, rest, end) {
      p = index(line, key "=\"")
      if (!p) return ""
      rest = substr(line, p + length(key) + 2)
      end = index(rest, "\"")
      if (!end) return ""
      return substr(rest, 1, end - 1)
    }
    function clean(value) {
      gsub(/[[:space:]]+/, " ", value)
      gsub(/\|/, "/", value)
      sub(/^ /, "", value)
      sub(/ $/, "", value)
      return value
    }
    function append(list, value, separator) {
      if (value == "") return list
      if (list == "") return value
      return list separator value
    }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line ~ /^<host[ >]/) {
        inhost = 1
        is_up = 0
        ip = ""
        dns = ""
        mac = ""
        open_ports = ""
        services = ""
        os_match = ""
        os_type = ""
        current_port = ""
        current_open = ""
        next
      }
      if (!inhost) next
      if (line ~ /^<status / && attr(line, "state") == "up") is_up = 1
      if (line ~ /^<address / && line ~ /addrtype="ipv4"/) ip = attr(line, "addr")
      if (line ~ /^<address / && line ~ /addrtype="mac"/) mac = attr(line, "addr")
      if (line ~ /^<hostname / && dns == "") dns = attr(line, "name")

      if (mode == "detail" && line ~ /^<port /) {
        current_port = attr(line, "portid") "/" attr(line, "protocol")
        current_open = ""
      }
      if (mode == "detail" && line ~ /^<state /) {
        if (attr(line, "state") == "open" && current_port != "") {
          open_ports = append(open_ports, current_port, ",")
          current_open = current_port
        }
      }
      if (mode == "detail" && line ~ /^<service /) {
        if (attr(line, "ostype") != "") os_type = clean(attr(line, "ostype"))
        if (current_open != "") {
          service = attr(line, "name")
          product = attr(line, "product")
          version = attr(line, "version")
          record = current_open
          if (service != "") record = record ":" service
          if (product != "") record = record ":" product
          if (version != "") record = record ":" version
          services = append(services, clean(record), ";")
          current_open = ""
        }
      }
      if (mode == "detail" && line ~ /^<osmatch / && os_match == "") {
        os_match = clean(attr(line, "name"))
      }

      if (line ~ /^<\/host>/) {
        if (is_up && ip != "") {
          if (os_match == "") os_match = os_type
          printf "%s|%s|%s|%s|%s|%s\n", ip, dns, mac, open_ports, services, os_match
        }
        inhost = 0
      }
    }
  '
}

if [[ -n "$INPUT_XML" ]]; then
  DISCOVERY_XML="$INPUT_XML"
  DETAIL_XML="$INPUT_XML"
  log "replaying Nmap XML: $INPUT_XML"
else
  log "discovering live hosts on $NETWORK"
  nmap -sn -R -oX "$DISCOVERY_XML" "$NETWORK"
fi

extract_ips "$DISCOVERY_XML" > "$TARGETS_FILE"
target_count="$(wc -l < "$TARGETS_FILE" | tr -d '[:space:]')"
((target_count > 0)) || die "Nmap found no live hosts on $NETWORK"

if [[ -z "$INPUT_XML" ]]; then
  DETAIL_ARGS=(nmap -Pn -R -T3 -sV --version-light -p "$PORTS")
  if ((EUID == 0)); then
    DETAIL_ARGS+=(-sS)
    if ((NO_OS == 0)); then DETAIL_ARGS+=(-O --osscan-limit); fi
  else
    DETAIL_ARGS+=(-sT)
    if ((NO_OS == 0)); then
      log "not running as root; skipping OS detection and using TCP connect scan"
    fi
  fi
  DETAIL_ARGS+=(-oX "$DETAIL_XML" -iL "$TARGETS_FILE")
  log "scanning $target_count live hosts on ports $PORTS"
  "${DETAIL_ARGS[@]}"
fi

parse_xml "$DISCOVERY_XML" discovery > "$DISCOVERY_DATA"
parse_xml "$DETAIL_XML" detail > "$DETAIL_DATA"
awk -F '|' '
  FNR == NR { discovery[$1] = $0; next }
  { details[$1] = $0 }
  END {
    for (ip in discovery) {
      if (ip in details) {
        split(discovery[ip], d, "|")
        split(details[ip], t, "|")
        # A non-root detail scan may omit MAC/DNS data found during discovery.
        # Keep those values instead of allowing the detail record to erase them.
        for (i = 2; i <= 3; i++) if (t[i] == "") t[i] = d[i]
        print t[1] "|" t[2] "|" t[3] "|" t[4] "|" t[5] "|" t[6]
      } else print discovery[ip]
    }
  }
' "$DISCOVERY_DATA" "$DETAIL_DATA" | sort -t '|' -k1,1 > "$MERGED_DATA"

HOST_DEFINITIONS="$WORK_DIR/host-definitions"
HOST_NAMES="$WORK_DIR/host-names"
SSH_MEMBERS="$WORK_DIR/ssh-members"
HTTP_MEMBERS="$WORK_DIR/http-members"
NFS_MEMBERS="$WORK_DIR/nfs-members"
LINUX_MEMBERS="$WORK_DIR/linux-members"
WINDOWS_MEMBERS="$WORK_DIR/windows-members"
OTHER_OS_MEMBERS="$WORK_DIR/other-os-members"
NO_OPEN_PORT_MEMBERS="$WORK_DIR/no-open-port-members"
: > "$HOST_DEFINITIONS"
: > "$HOST_NAMES"
: > "$SSH_MEMBERS"
: > "$HTTP_MEMBERS"
: > "$NFS_MEMBERS"
: > "$LINUX_MEMBERS"
: > "$WINDOWS_MEMBERS"
: > "$OTHER_OS_MEMBERS"
: > "$NO_OPEN_PORT_MEMBERS"

yaml_quote() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\r'/ }
  value=${value//$'\n'/ }
  value=${value//$'\t'/ }
  printf '"%s"' "$value"
}

yaml_list() {
  local value="$1"
  local separator="${2:-,}"
  local item
  local first=1
  [[ -n "$value" ]] || { printf '[]'; return; }
  printf '['
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    if ((first)); then first=0; else printf ', '; fi
    yaml_quote "$item"
  done < <(printf '%s' "$value" | tr "$separator" '\n')
  printf ']'
}

has_port() {
  [[ ",$1," == *",$2,"* ]]
}

alias_for_ip() {
  local ip="$1"
  printf 'scan_%s' "${ip//./_}"
}

SCAN_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
while IFS='|' read -r ip dns mac open_ports services os || [[ -n "$ip" ]]; do
  [[ -n "$ip" ]] || continue
  alias="$(alias_for_ip "$ip")"
  short_hostname=""
  [[ -n "$dns" ]] && short_hostname="${dns%%.*}"
  {
    printf '            %s:\n' "$alias"
    printf '              ansible_host: '; yaml_quote "$ip"; printf '\n'
    printf '              discovered_ip: '; yaml_quote "$ip"; printf '\n'
    printf '              discovered_dns: '; yaml_quote "$dns"; printf '\n'
    printf '              discovered_hostname: '; yaml_quote "$short_hostname"; printf '\n'
    printf '              discovered_mac: '; yaml_quote "$mac"; printf '\n'
    printf '              discovered_open_ports: '; yaml_list "$open_ports" ','; printf '\n'
    printf '              discovered_services: '; yaml_list "$services" ';'; printf '\n'
    printf '              discovered_os: '; yaml_quote "$os"; printf '\n'
    printf '              discovered_scan_network: '; yaml_quote "$NETWORK"; printf '\n'
    printf '              discovered_scan_time: '; yaml_quote "$SCAN_TIME"; printf '\n'
  } >> "$HOST_DEFINITIONS"
  printf '            %s:\n' "$alias" >> "$HOST_NAMES"

  os_lower="${os,,}"
  services_lower="${services,,}"
  if has_port "$open_ports" 22/tcp || has_port "$open_ports" 2222/tcp ||
     has_port "$open_ports" 2223/tcp || [[ "$services_lower" == *ssh* ]]; then
    printf '            %s:\n' "$alias" >> "$SSH_MEMBERS"
  fi
  if has_port "$open_ports" 80/tcp || has_port "$open_ports" 443/tcp ||
     has_port "$open_ports" 8080/tcp || has_port "$open_ports" 8443/tcp; then
    printf '            %s:\n' "$alias" >> "$HTTP_MEMBERS"
  fi
  if has_port "$open_ports" 2049/tcp || has_port "$open_ports" 2049/udp; then
    printf '            %s:\n' "$alias" >> "$NFS_MEMBERS"
  fi
  if [[ "$os_lower" == *windows* ]]; then
    printf '            %s:\n' "$alias" >> "$WINDOWS_MEMBERS"
  elif [[ "$os_lower" == *linux* || "$os_lower" == *ubuntu* ||
          "$os_lower" == *debian* || "$os_lower" == *red\ hat* ||
          "$os_lower" == *centos* || "$os_lower" == *fedora* ]]; then
    printf '            %s:\n' "$alias" >> "$LINUX_MEMBERS"
  elif [[ -n "$os" ]]; then
    printf '            %s:\n' "$alias" >> "$OTHER_OS_MEMBERS"
  fi
  [[ -n "$open_ports" ]] || printf '            %s:\n' "$alias" >> "$NO_OPEN_PORT_MEMBERS"
done < "$MERGED_DATA"

emit_group() {
  local group_name="$1"
  local members_file="$2"
  if [[ -s "$members_file" ]]; then
    printf '        %s:\n          hosts:\n' "$group_name"
    cat "$members_file"
  else
    printf '        %s:\n          hosts: {}\n' "$group_name"
  fi
}

OUTPUT_DIR="$(dirname -- "$OUTPUT")"
mkdir -p -- "$OUTPUT_DIR"
TEMP_OUTPUT="$WORK_DIR/discovered_hosts.yml"
{
  printf '%s\n' '---'
  printf '# Generated by scripts/scan_inventory.sh. Do not edit manually.\n'
  printf '# Regenerate this file after reviewing the scan results.\n'
  printf 'all:\n  children:\n    discovered:\n      children:\n        discovered_hosts:\n          hosts:\n'
  cat "$HOST_DEFINITIONS"
  emit_group discovered_ssh "$SSH_MEMBERS"
  emit_group discovered_http "$HTTP_MEMBERS"
  emit_group discovered_nfs "$NFS_MEMBERS"
  emit_group discovered_linux "$LINUX_MEMBERS"
  emit_group discovered_windows "$WINDOWS_MEMBERS"
  emit_group discovered_other_os "$OTHER_OS_MEMBERS"
  emit_group discovered_no_open_ports "$NO_OPEN_PORT_MEMBERS"
  if [[ -n "$ATTACH_GROUP" ]]; then
    printf '    %s:\n      hosts:\n' "$ATTACH_GROUP"
    cat "$HOST_NAMES"
  fi
} > "$TEMP_OUTPUT"
mv -f -- "$TEMP_OUTPUT" "$OUTPUT"

if [[ -n "$SCAN_DIR" ]]; then
  mkdir -p -- "$SCAN_DIR"
  cp -- "$DISCOVERY_XML" "$SCAN_DIR/discovery.xml"
  cp -- "$DETAIL_XML" "$SCAN_DIR/details.xml"
  cp -- "$TARGETS_FILE" "$SCAN_DIR/targets.txt"
fi

host_count="$(wc -l < "$HOST_NAMES" | tr -d '[:space:]')"
log "wrote $host_count discovered hosts to $OUTPUT"
[[ -z "$ATTACH_GROUP" ]] || log "attached discovered hosts to group $ATTACH_GROUP"
