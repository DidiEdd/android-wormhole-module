# android-wormhole-module
Create a file system Wormhole between Android users!

Have you ever wanted to bring files from one userspace to another on Android? Now you can!
With the help of Google Gemini, I have built an alpha module for Magisk/KernelSU/aPatcher/etc. that allows you to transfer files between any users on your phone! This code is very preliminary, so there are many limitations and it is very simple. I have plans to update it only if it receives interest.

# Key Features

- Creates a virtually shared folder between multiple userspaces on Android.

- Uses no extra space: The files are not duplicated; they are simply "redirected" and "reowned" upon switching the userspace.

- Extremely light on resources and small size: Polling is kept to a minimum, so you won't have to worry about any battery drain or CPU usage.

# Limitations

- **Requires root**: This module only works if you have rooted your Android device using a method that supports Magisk modules. It seems just barely possible to even do what I've just accomplished with root, let alone without it...

- Currently, only one folder labeled "Wormhole" is created at /storage/0/ using this module, across any existing users on the device. This folder serves as a Wormhole between each userspace and there is currently no option to move it or add additional wormholes, though this is not particularly difficult to do. I just don't want to deal with learning how to create a working UI for this, so I won't waste my time for now unless these features are requested.

- There may be some slight synchronization issues occasionally. I've optimized this to the best of my understanding, but further optimization may be looked into.

- I don't have a clue what version of Android this doesn't work for, and so on. Tested on Pixel 8a running stock Android 16. It may or may not work, use at your own risk I guess...