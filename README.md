# Night Shift Dorm (Godot 4.2+)

Original co-op game. 1-4 players. Sleep = coins, awake = repair door, Door+/Bed+ = upgrades. Survive 150s.

## Build the APK
1. Install Godot 4.2+ (with Export Templates), JDK 17, Android SDK (Godot: Editor Settings > Export > Android).
2. Open this folder as a project.
3. Project > Export > Add > Android. Under Permissions enable:
   Internet, Access Network State, Access Wifi State, Change Wifi Multicast State.
4. Export Project (.apk). Install on each phone.

## LAN / hotspot (no codes)
Host phone: turn on hotspot > LAN / Hotspot: Host.
Other phones: join that hotspot > Find games > tap the room.
(Host broadcasts via UDP port 24568; game uses UDP 24567.)
If a router/hotspot blocks broadcast, use "Online: Join server" with the host's IP.

## Online
Run a dedicated server (any Linux VPS with UDP 24567 open):
    ./nightshift.x86_64 --headless -- --server
Players enter the server's IP/domain under Online > Join.

NOTE: not yet run-tested in the Godot editor; expect small fixes.

## No-setup APK build (GitHub)
1. Create a new GitHub repo and upload this folder's contents.
2. Actions tab > "Build Android APK" > Run workflow.
3. Download NightShiftDorm-apk from the finished run, send the .apk to phones, install
   (allow "install unknown apps"). It is debug-signed, which is fine for sideloading.

## v2 features
3 nights (90s each, harder each night), 3 ghost types (Poltergeist fast/weak, Brute slow/heavy from night 2,
Wraith hits sleepers harder from night 3), upgrades: Door+, Bed+, Salt (less damage), Night-light (door regen),
dawn bonus coins, procedural sound effects, screen shake, ghost-warning flash.
