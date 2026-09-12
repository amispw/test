#!/usr/bin/env bash
# =============================================================================
#  DIAGNOSTIC POSTE DE TRAVAIL DISTANT  --  100% LECTURE SEULE
# =============================================================================
#  Ce script NE MODIFIE RIEN. Il lit la configuration de la machine et affiche
#  un rapport. Aucune ecriture disque, aucun paquet installe, aucun service
#  demarre ou arrete, aucun fichier de configuration touche.
#
#  Usage depuis le portable :
#      ssh utilisateur@tour 'bash -s' < diagnostic-tour.sh
#  ou, une fois copie sur la machine :
#      bash diagnostic-tour.sh
#
#  Sudo n'est PAS requis. Certaines lignes seront simplement moins detaillees.
# =============================================================================

set -u

H()  { printf '\n%s\n  %s\n%s\n' "$(printf '=%.0s' {1..70})" "$1" "$(printf '=%.0s' {1..70})"; }
KV() { printf '  %-30s: %s\n' "$1" "${2:-n/a}"; }
have() { command -v "$1" >/dev/null 2>&1; }

echo "RAPPORT DIAGNOSTIC — POSTE DE TRAVAIL DISTANT"
echo "Genere le $(date '+%Y-%m-%d %H:%M:%S')"
echo "Mode : LECTURE SEULE — aucune modification effectuee"

# --- 1. Systeme -------------------------------------------------------------
H "1. SYSTEME"
if [ -r /etc/os-release ]; then
  . /etc/os-release
  KV "Distribution"    "${PRETTY_NAME:-$NAME $VERSION_ID}"
  KV "Identifiant"     "${ID:-?} ${VERSION_ID:-}"
else
  KV "Distribution" "/etc/os-release absent — ce n'est peut-etre pas un Linux"
fi
KV "Noyau"           "$(uname -r)"
KV "Architecture"    "$(uname -m)"
KV "Nom d'hote"      "$(hostname 2>/dev/null)"
KV "Utilisateur"     "$(id -un) (uid $(id -u))"
KV "Uptime"          "$(uptime -p 2>/dev/null || uptime)"

if have systemd-detect-virt; then
  V=$(systemd-detect-virt 2>/dev/null || echo none)
  KV "Virtualisation" "$([ "$V" = none ] && echo 'machine physique' || echo "$V")"
fi
grep -qi microsoft /proc/version 2>/dev/null && \
  echo "  !!! WSL detecte : ce n'est pas une machine Linux autonome."

# --- 2. Interface graphique -------------------------------------------------
H "2. MODE D'EXECUTION"
SESS="headless (aucun serveur graphique)"
[ -n "${DISPLAY:-}"          ] && SESS="graphique X11 ($DISPLAY)"
[ -n "${WAYLAND_DISPLAY:-}"  ] && SESS="graphique Wayland"
if have systemctl; then
  TGT=$(systemctl get-default 2>/dev/null || echo '?')
  KV "Cible systemd par defaut" "$TGT"
  [ "$TGT" = "multi-user.target" ] && SESS="headless (multi-user.target)"
fi
KV "Session courante" "$SESS"
KV "Bureau installe"  "$(have gnome-shell && echo GNOME || (have plasmashell && echo KDE || echo 'aucun detecte'))"

# --- 3. CPU / RAM -----------------------------------------------------------
H "3. PUISSANCE DISPONIBLE"
if have lscpu; then
  KV "Processeur"  "$(lscpu | awk -F: '/Model name/{gsub(/^ +/,"",$2);print $2;exit}')"
  KV "Coeurs / threads" "$(lscpu | awk -F: '/^Core\(s\) per socket/{gsub(/ /,"",$2);c=$2} /^Socket\(s\)/{gsub(/ /,"",$2);s=$2} END{print c*s" / "'"$(nproc)"'}')"
else
  KV "Processeur" "$(awk -F: '/model name/{gsub(/^ +/,"",$2);print $2;exit}' /proc/cpuinfo)"
  KV "Threads"    "$(nproc)"
fi
if have free; then
  KV "RAM totale"     "$(free -h | awk '/^Mem:/{print $2}')"
  KV "RAM disponible" "$(free -h | awk '/^Mem:/{print $7}')"
  KV "Swap"           "$(free -h | awk '/^Swap:/{print $2}')"
fi

# --- 4. GPU -----------------------------------------------------------------
H "4. CARTE GRAPHIQUE  (compte pour le streaming du bureau)"
if have nvidia-smi && nvidia-smi -L >/dev/null 2>&1; then
  nvidia-smi -L | sed 's/^/  /'
  KV "Pilote NVIDIA" "$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)"
elif have lspci; then
  lspci 2>/dev/null | grep -Ei 'vga|3d controller|display' | sed 's/^/  /' || echo "  aucune detectee"
else
  echo "  lspci absent — impossible de determiner"
fi

# --- 5. Stockage ------------------------------------------------------------
H "5. STOCKAGE  (decide entre disque dedie et partition)"
if have lsblk; then
  echo "  Disques et partitions :"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL 2>/dev/null | sed 's/^/    /'
else
  echo "  lsblk absent"
fi
echo
echo "  Espace libre par systeme de fichiers :"
df -h -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | sed 's/^/    /'

# --- 6. Reseau --------------------------------------------------------------
H "6. RESEAU"
if have ip; then
  ip -brief addr show 2>/dev/null | grep -v '^lo' | sed 's/^/  /'
elif have ifconfig; then
  ifconfig -a 2>/dev/null | grep -E '^[a-z]|inet ' | sed 's/^/  /'
else
  echo "  ni 'ip' ni 'ifconfig' disponibles"
fi
echo
for i in $(ls /sys/class/net 2>/dev/null | grep -v '^lo$'); do
  SP=$(cat "/sys/class/net/$i/speed" 2>/dev/null || echo '?')
  if [ "$SP" != "?" ] && [ "$SP" -gt 0 ] 2>/dev/null; then
    KV "Debit lien $i" "${SP} Mb/s"
  else
    KV "Lien $i" "present (debit non expose — sans-fil ou virtuel)"
  fi
done
KV "Passerelle" "$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')"

# --- 7. SSH -----------------------------------------------------------------
H "7. SERVEUR SSH  (a durcir avant toute exposition)"
SSHD=/etc/ssh/sshd_config
if [ -r "$SSHD" ]; then
  eff() {
    V=$(grep -hiE "^[[:space:]]*$1[[:space:]]" "$SSHD" /etc/ssh/sshd_config.d/*.conf 2>/dev/null \
        | tail -1 | awk '{print $2}')
    echo "${V:-defaut}"
  }
  KV "Port"                  "$(eff Port)"
  KV "PermitRootLogin"       "$(eff PermitRootLogin)"
  KV "PasswordAuthentication" "$(eff PasswordAuthentication)"
  KV "PubkeyAuthentication"  "$(eff PubkeyAuthentication)"
else
  KV "sshd_config" "illisible sans privileges"
fi
KV "Cles autorisees" "$( [ -r "$HOME/.ssh/authorized_keys" ] && grep -c '^ssh-\|^ecdsa-\|^sk-' "$HOME/.ssh/authorized_keys" 2>/dev/null || echo 0 ) entree(s)"
if have systemctl; then
  KV "Service sshd" "$(systemctl is-active sshd 2>/dev/null || systemctl is-active ssh 2>/dev/null || echo '?')"
fi
have fail2ban-client && KV "fail2ban" "installe" || KV "fail2ban" "absent"

# --- 8. Outillage -----------------------------------------------------------
H "8. OUTILLAGE DEJA PRESENT"
for c in git docker podman tmux mosh zsh curl jq rsync node python3 go rustc tailscale; do
  if have "$c"; then
    case "$c" in
      tmux) VER=$(tmux -V 2>&1) ;;
      go)   VER=$(go version 2>&1) ;;
      *)    VER=$("$c" --version 2>&1 | head -1) ;;
    esac
    printf '  %-12s : %s\n' "$c" "$(echo "$VER" | head -1 | cut -c1-58)"
  else
    printf '  %-12s : absent\n' "$c"
  fi
done

# --- 9. Services 24/7 -------------------------------------------------------
H "9. SERVICES ACTUELLEMENT ACTIFS"
if have systemctl; then
  systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null \
    | awk '{print $1}' | grep -vE '^(systemd-|dbus|user@|getty|polkit|cron|rsyslog)' \
    | head -15 | sed 's/^/  /'
else
  echo "  systemd absent"
fi

# --- 10. Mise en veille -----------------------------------------------------
H "10. APTITUDE AU FONCTIONNEMENT 24/7"
if have systemctl; then
  for u in sleep.target suspend.target hibernate.target; do
    KV "$u" "$(systemctl is-enabled $u 2>/dev/null || echo '?')"
  done
  echo "  (masked = la machine ne se mettra jamais en veille : souhaitable pour un serveur)"
fi

H "SYNTHESE"
echo "  Points a decider a partir de ce rapport :"
echo "   1. La machine est-elle deja sous Linux, ou faut-il l'installer ?"
echo "   2. Y a-t-il un disque libre pour un systeme dedie, ou faut-il partitionner ?"
echo "   3. GPU present -> streaming du bureau possible, sinon SSH/terminal seulement."
echo "   4. PasswordAuthentication doit passer a 'no' apres installation des cles."
echo "   5. Les cibles de veille doivent etre masquees pour un usage 24/7."
echo
echo "Termine. Aucune modification n'a ete faite sur cette machine."
