ui_print "- Android Wormhole v0.1.0"
D=/data/adb/wormhole
mkdir -p "$D"
[ -f "$D/daemon.pid" ] && kill "$(cat "$D/daemon.pid")" 2>/dev/null
set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in wormhole.sh service.sh action.sh uninstall.sh; do set_perm "$MODPATH/$f" 0 0 0755; done
ui_print "- Settings live in $D and survive updates"
ui_print "- Reboot, then open the WebUI from the module list"
