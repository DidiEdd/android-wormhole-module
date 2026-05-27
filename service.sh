#!/system/bin/sh
# Magisk system variable path resolution
MODDIR=${0%/*}

LOG_FILE="/data/local/tmp/wormhole.log"
echo "=== Wormhole System Module Started at $(date) ===" > $LOG_FILE
chmod 666 $LOG_FILE

# 1. Wait for primary system storage setup to verify primary storage is up
while [ ! -d "/data/media/0/Android" ]; do
    sleep 2
done

mkdir -p /data/media/0/Wormhole
chown media_rw:media_rw /data/media/0/Wormhole
chmod 775 /data/media/0/Wormhole
echo "Config: Admin base directory verified." >> $LOG_FILE

# Initialize persistent memory state flags for tracking user encryption statuses
USER_0_UNLOCKED=true
USER_10_UNLOCKED=false
USER_11_UNLOCKED=false

# 2. Optimized Handoff Engine
handoff_wormhole() {
    TARGET_USER="$1"
    REASON="$2"
    
    echo "Trigger: Handoff invoked for User $TARGET_USER due to [$REASON] at $(date)" >> $LOG_FILE
    mkdir -p /data/media/$TARGET_USER/Wormhole 2>>$LOG_FILE
    
    for CURRENT_USER in 0 10 11; do
        if [ "$CURRENT_USER" != "$TARGET_USER" ]; then
            if [ -d "/data/media/$CURRENT_USER/Wormhole" ] && [ "$(ls -A /data/media/$CURRENT_USER/Wormhole 2>/dev/null)" ]; then
                echo "Action: Moving files from User $CURRENT_USER to $TARGET_USER..." >> $LOG_FILE
                mv -f /data/media/$CURRENT_USER/Wormhole/* /data/media/$TARGET_USER/Wormhole/ 2>>$LOG_FILE
            fi
        fi
    done
    
    chown -R media_rw:media_rw /data/media/$TARGET_USER/Wormhole 2>>$LOG_FILE
    chmod -R 775 /data/media/$TARGET_USER/Wormhole 2>>$vi LOG_FILE
    
    am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE --user $TARGET_USER -d "file:///storage/emulated/$TARGET_USER/Wormhole" >/dev/null 2>&1
    echo "Action: Handoff execution complete for User $TARGET_USER" >> $LOG_FILE
}

# Run initial boot scan
INITIAL_USER=$(am get-current-user 2>/dev/null || echo "0")
handoff_wormhole "$INITIAL_USER" "Boot Init"

# Set initial tracking baselines
LAST_USER="$INITIAL_USER"
LAST_HANDOFF_TIME=$(date +%s)
DEBOUNCE_DELAY=3 

echo "Config: Starting LIVE optimized passive logcat stream..." >> $LOG_FILE

# 3. Intelligent Event Listener with Debouncing and State Gates
logcat -b system -b events -T 1 | while read -r line; do
    if echo "$line" | grep -qE "startUser-|onSwitchUser-|unlockUser-|finishUserUnlocking"; then
        
        TARGET_USER=$(echo "$line" | grep -oE "(startUser-|onSwitchUser-|unlockUser-)[0-9]+" | grep -oE "[0-9]+")
        [ -z "$TARGET_USER" ] && TARGET_USER=$(am get-current-user 2>/dev/null || echo "0")
        
        if [ "$TARGET_USER" = "0" ] || [ "$TARGET_USER" = "10" ] || [ "$TARGET_USER" = "11" ]; then
            
            CURRENT_TIME=$(date +%s)
            TIME_DIFF=$((CURRENT_TIME - LAST_HANDOFF_TIME))
            eval CURRENT_STATUS=\$USER_${TARGET_USER}_UNLOCKED
            
            if [ "$CURRENT_STATUS" = "true" ]; then
                if [ "$TARGET_USER" != "$LAST_USER" ] || [ "$TIME_DIFF" -gt "$DEBOUNCE_DELAY" ]; then
                    echo "Gatekeeper: User $TARGET_USER already verified unlocked. Running fast-path transfer." >> $LOG_FILE
                    handoff_wormhole "$TARGET_USER" "Fast Path Switch"
                    LAST_USER="$TARGET_USER"
                    LAST_HANDOFF_TIME=$CURRENT_TIME
                fi
            else
                mkdir -p /data/media/$TARGET_USER/Wormhole 2>/dev/null
                touch /data/media/$TARGET_USER/Wormhole/.probe 2>/dev/null
                
                if [ $? -eq 0 ]; then
                    rm -f /data/media/$TARGET_USER/Wormhole/.probe
                    eval USER_${TARGET_USER}_UNLOCKED=true
                    echo "Gatekeeper: User $TARGET_USER decrypted for the first time!" >> $LOG_FILE
                    handoff_wormhole "$TARGET_USER" "First Unlock Core Trigger"
                    LAST_USER="$TARGET_USER"
                    LAST_HANDOFF_TIME=$CURRENT_TIME
                else
                    echo "Gatekeeper: Caught line for User $TARGET_USER but storage is locked. Dropping log entry." >> $LOG_FILE
                fi
            fi
        fi
    fi
done
