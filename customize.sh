# Setup message terminal banner
ui_print "**************************************"
ui_print "      Installing Android Wormhole®     "
ui_print "**************************************"
ui_print "- Setting up shared boundary links..."

# Enforce early directory staging on target systems
mkdir -p /data/media/0/Wormhole
set_perm /data/media/0/Wormhole media_rw media_rw 775

ui_print "- Injection preparation successful!"
ui_print "- Please reboot your device to launch the Wormhole."
