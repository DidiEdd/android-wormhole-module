#!/system/bin/sh
# Android Wormhole core: background service + CLI used by the WebUI.
MODDIR=${0%/*}
MEDIA=${WORMHOLE_MEDIA:-/data/media}
DATA=${WORMHOLE_DATA:-/data/adb/wormhole}
CFG=$DATA/config.sh; LOG=$DATA/wormhole.log; LOCK=$DATA/lock.d; PIDF=$DATA/daemon.pid
mkdir -p "$DATA"
KEYS="ENABLED WORMHOLES INTERVAL SETTLE ON_CONFLICT NORMALIZE FIX_SELINUX DIR_MODE FILE_MODE MEDIA_SCAN NOMEDIA EXCLUDE_USERS EXCLUDE_PROFILES CLEAN_DAYS NOTIFY LOG_KB"

load() {
  ENABLED=1 WORMHOLES="Wormhole" INTERVAL=3 SETTLE=2 ON_CONFLICT=rename
  NORMALIZE=1 FIX_SELINUX=1 DIR_MODE=0775 FILE_MODE=0664
  MEDIA_SCAN=1 NOMEDIA=0 EXCLUDE_USERS="" EXCLUDE_PROFILES=1
  CLEAN_DAYS=0 NOTIFY=0 LOG_KB=256
  [ -f "$CFG" ] && . "$CFG"
}
log() {
  echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"
  [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt $((${LOG_KB:-256} * 1024)) ] &&
    tail -n 300 "$LOG" > "$LOG.t" && mv "$LOG.t" "$LOG"
}
all_users() { for d in "$MEDIA"/[0-9]*; do u=${d##*/}; case $u in *[!0-9]*) ;; *) echo "$u";; esac; done; }
# A locked (FBE) user shows encrypted names, so "Android" only resolves once unlocked.
unlocked() { [ -d "$MEDIA/$1/Android" ]; }
uinfo() { { cmd user list || pm list users; } 2>/dev/null | sed -n 's/.*UserInfo{\([0-9]*\):\(.*\):\([0-9a-f]*\)}.*/\1|\2|\3/p'; }
elig() {
  us=$(all_users)
  if [ "$us" != "$UCACHE" ]; then UCACHE=$us; UINFO=$(uinfo); fi
  for u in $us; do
    case " $EXCLUDE_USERS " in *" $u "*) continue;; esac
    if [ "$EXCLUDE_PROFILES" = 1 ]; then
      fl=$(echo "$UINFO" | sed -n "s/^$u|.*|\([0-9a-f]*\)$/\1/p")
      [ -n "$fl" ] && [ $((0x$fl & 0x1000)) -ne 0 ] && continue
    fi
    echo "$u"
  done
}
# Owner, mode and SELinux label normalisation (this is what lets any user delete files).
fixnode() {
  fm=$2
  if [ "$NORMALIZE" = 1 ] || [ "$fm" = force ]; then
    chown -R media_rw:media_rw "$1" 2>>"$LOG"
    find "$1" -type d -exec chmod "$DIR_MODE" {} + 2>>"$LOG"
    find "$1" -type f -exec chmod "$FILE_MODE" {} + 2>>"$LOG"
  fi
  if [ "$FIX_SELINUX" = 1 ] || [ "$fm" = force ]; then
    restorecon -RF "$1" 2>>"$LOG" || chcon -R u:object_r:media_rw_data_file:s0 "$1" 2>>"$LOG"
  fi
}
scan() { [ "$MEDIA_SCAN" = 1 ] && content call --user "$1" --uri content://media/ --method scan_file --arg "/storage/emulated/$1/$2" >/dev/null 2>&1; }
ensure() {
  d=$MEDIA/$1/$2
  if [ ! -d "$d" ]; then
    mkdir -p "$d" 2>/dev/null || return 0
    chown media_rw:media_rw "$d"; chmod "$DIR_MODE" "$d"; restorecon -F "$d" 2>/dev/null
    log "created $d"
  fi
  if [ "$NOMEDIA" = 1 ]; then
    [ -e "$d/.nomedia" ] || { : > "$d/.nomedia"; chown media_rw:media_rw "$d/.nomedia"; }
  else
    [ -e "$d/.nomedia" ] && rm -f "$d/.nomedia"
  fi
}
# Move everything from other users' folder $2 into user $1's folder.
pull() {
  T=$1; W=$2; dst=$MEDIA/$T/$W; moved=0; tl=""
  for U in $E; do
    [ "$U" = "$T" ] && continue
    src=$MEDIA/$U/$W; [ -d "$src" ] || continue
    for f in "$src"/* "$src"/.[!.]* "$src"/..?*; do
      [ -e "$f" ] || [ -L "$f" ] || continue
      n=${f##*/}; [ "$n" = .nomedia ] && continue
      if [ "${SETTLE:-0}" -gt 0 ]; then
        [ $(( $(date +%s) - $(stat -c %Y "$f" 2>/dev/null || echo 0) )) -lt "$SETTLE" ] && continue
      fi
      t=$dst/$n
      if [ -e "$t" ] || [ -L "$t" ]; then
        case $ON_CONFLICT in
          skip) continue;;
          overwrite) rm -rf "$t";;
          newer) [ "$f" -nt "$t" ] || continue; rm -rf "$t";;
          *) b=$n; e=""; case $n in ?*.*) b=${n%.*}; e=.${n##*.};; esac
             i=1; while [ -e "$dst/$b (user$U-$i)$e" ]; do i=$((i + 1)); done
             t="$dst/$b (user$U-$i)$e";;
        esac
      fi
      if mv "$f" "$t" 2>>"$LOG"; then
        moved=$((moved + 1)); fixnode "$t"
        case " $tl " in *" $U "*) ;; *) tl="$tl $U";; esac
        log "moved user$U/$W/$n -> user$T/${t#$dst/}"
      else log "FAILED to move $f"; fi
    done
  done
  if [ "$moved" -gt 0 ]; then
    scan "$T" "$W"; for U in $tl; do scan "$U" "$W"; done
    [ "$NOTIFY" = 1 ] && cmd notification post -t Wormhole wormhole "$moved item(s) arrived in $W" >/dev/null 2>&1
  fi
}
clean() {
  [ "${CLEAN_DAYS:-0}" -gt 0 ] || return 0
  now=$(date +%s); [ $((now - ${LASTCLEAN:-0})) -ge 3600 ] || return 0; LASTCLEAN=$now
  for W in $WORMHOLES; do
    d=$MEDIA/$CUR/$W; [ -d "$d" ] || continue
    find "$d" -mindepth 1 -type f ! -name .nomedia -mtime +"$CLEAN_DAYS" -delete 2>>"$LOG"
    find "$d" -mindepth 1 -type d -empty -delete 2>>"$LOG"
  done
  log "auto-clean: removed files older than $CLEAN_DAYS days"
}
lock() {
  mkdir "$LOCK" 2>/dev/null && return 0
  [ -n "$(find "$LOCK" -maxdepth 0 -mmin +2 2>/dev/null)" ] && { rmdir "$LOCK"; mkdir "$LOCK" 2>/dev/null; return; }
  return 1
}
sync_once() {
  lock || { echo busy; return 0; }
  CUR=$(cmd activity get-current-user 2>/dev/null); case $CUR in ''|*[!0-9]*) CUR=0;; esac
  E=$(elig); E=$(echo $E)
  for W in $WORMHOLES; do
    for u in $E; do
      unlocked "$u" || continue
      ensure "$u" "$W"
      case " $SEEN " in *" $u:$W "*) ;; *) SEEN="$SEEN $u:$W"; fixnode "$MEDIA/$u/$W"; scan "$u" "$W";; esac
    done
    case " $E " in *" $CUR "*) unlocked "$CUR" && pull "$CUR" "$W";; esac
  done
  clean; rmdir "$LOCK" 2>/dev/null
}
daemon() {
  p=$(cat "$PIDF" 2>/dev/null)
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null && grep -q wormhole "/proc/$p/cmdline" 2>/dev/null && exit 0
  echo $$ > "$PIDF"; load; log "service started (pid $$)"
  while :; do load; [ "$ENABLED" = 1 ] && sync_once; sleep "$INTERVAL"; done
}
setcfg() {
  k=$1; v=$2; ok=0
  case " $KEYS " in *" $k "*) ;; *) echo "unknown setting"; exit 1;; esac
  case $k in
    ENABLED|NORMALIZE|FIX_SELINUX|MEDIA_SCAN|NOMEDIA|EXCLUDE_PROFILES|NOTIFY) { [ "$v" = 0 ] || [ "$v" = 1 ]; } && ok=1;;
    INTERVAL|SETTLE|CLEAN_DAYS|LOG_KB) case $v in ''|*[!0-9]*) ;; *) [ ${#v} -le 5 ] && ok=1;; esac
      [ "$k" = INTERVAL ] && [ "$ok" = 1 ] && [ "$v" -lt 1 ] && ok=0;;
    DIR_MODE|FILE_MODE) case $v in ''|*[!0-7]*) ;; *) [ ${#v} -ge 3 ] && [ ${#v} -le 4 ] && ok=1;; esac;;
    ON_CONFLICT) case $v in rename|skip|overwrite|newer) ok=1;; esac;;
    WORMHOLES) case $v in ''|*[!A-Za-z0-9._\ -]*|*..*|*[Aa]ndroid*) ;; *) ok=1;; esac
      for w in $v; do [ "$w" = . ] && ok=0; done; [ -z "$(echo $v)" ] && ok=0;;
    EXCLUDE_USERS) case $v in *[!0-9\ ]*) ;; *) ok=1;; esac;;
  esac
  [ "$ok" = 1 ] || { echo "invalid value for $k"; exit 1; }
  touch "$CFG"; grep -v "^$k=" "$CFG" > "$CFG.t"; echo "$k=\"$v\"" >> "$CFG.t"; mv "$CFG.t" "$CFG"; echo ok
}
status() {
  load; p=$(cat "$PIDF" 2>/dev/null); d=0
  [ -n "$p" ] && grep -q wormhole "/proc/$p/cmdline" 2>/dev/null && d=1
  echo "daemon=$d"; echo "current=$(cmd activity get-current-user 2>/dev/null)"
  echo "version=$(sed -n 's/^version=//p' "$MODDIR/module.prop")"
  info=$(uinfo)
  for u in $(all_users); do
    n=$(echo "$info" | sed -n "s/^$u|\(.*\)|[0-9a-f]*$/\1/p"); fl=$(echo "$info" | sed -n "s/^$u|.*|\([0-9a-f]*\)$/\1/p")
    l=0; c=0; s=0
    if unlocked "$u"; then
      l=1
      for W in $WORMHOLES; do
        [ -d "$MEDIA/$u/$W" ] || continue
        c=$((c + $(ls -A "$MEDIA/$u/$W" | grep -vc '^\.nomedia$')))
        s=$((s + $(du -sk "$MEDIA/$u/$W" | cut -f1)))
      done
    fi
    echo "user=$u|$n|$l|${fl:-0}|$c|$s"
  done
}
diag() {
  load; echo "# owner, mode and SELinux label"
  for u in $(all_users); do
    unlocked "$u" || { echo "user $u: storage locked"; continue; }
    ls -ldZ "$MEDIA/$u" "$MEDIA/$u/Android"
    for W in $WORMHOLES; do ls -ldZ "$MEDIA/$u/$W"; ls -lAZ "$MEDIA/$u/$W" | head -n 8; done
  done
  echo; echo "# recent SELinux denials"
  dmesg 2>/dev/null | grep -i 'avc: *denied' | grep -iE 'media_rw|wormhole|fuse' | tail -n 12
}
repair() {
  load
  for u in $(elig); do
    unlocked "$u" || continue
    for W in $WORMHOLES; do ensure "$u" "$W"; fixnode "$MEDIA/$u/$W" force; scan "$u" "$W"; log "repaired $MEDIA/$u/$W"; done
  done
  echo done
}
case "$1" in
  daemon) daemon;;
  sync) load; sync_once; echo done;;
  status) status;;
  get) load; for k in $KEYS; do eval "echo $k=\"\$$k\""; done;;
  set) setcfg "$2" "$3";;
  log) tail -n "${2:-80}" "$LOG" 2>/dev/null;;
  diag) diag;;
  repair) repair;;
  restart) kill "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; rm -f "$PIDF"; (setsid sh "$0" daemon >/dev/null 2>&1 &); echo restarted;;
  *) echo "usage: wormhole.sh daemon|sync|status|get|set K V|log [n]|diag|repair|restart";;
esac
