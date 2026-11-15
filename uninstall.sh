#!/system/bin/sh
kill "$(cat /data/adb/wormhole/daemon.pid 2>/dev/null)" 2>/dev/null
rm -rf /data/adb/wormhole
