# Fehler-, Lösungs- & System-Protokoll (SnowFoxOS)

| Status | Was hat nicht funktioniert? / Was soll gemacht werden? | Ursache / Details | Wie haben wir es behoben? / Ansatz |
| :--- | :--- | :--- | :--- |
| **Erledigt** | **X11 / startx startete nur mit sudo** | Der X-Server blockiert normalen Benutzern den Zugriff auf die physische Konsole (TTY). | In `/etc/X11/Xwrapper.config` die Zeile `allowed_users=anybody` eingetragen. |
| **Erledigt** | **System fror beim Starten von X11 / i3 komplett ein** | Realtek-WLAN-Chip erzeugte massenhaft PCIe-Bus-Fehler (AER), was den Kernel blockierte. | In `/etc/default/grub` den Parameter `pci=noaer` hinzugefügt. |
| **Erledigt** | **WLAN-Karte (wlo1) war komplett "nicht verfügbar"** | Die alte Debian-Netzwerkkonfiguration (`ifupdown`) hat die Karte exklusiv blockiert. | Einträge in `/etc/network/interfaces` auskommentiert und an den NetworkManager übergeben. |
| **Erledigt** | **WLAN-Treiber wurde im XanMod-Kernel nicht gefunden** | Durch das Kernel-Update hat sich der Modulname geändert (Unterstrich fiel weg). | Das Modul mit dem neuen Namen `rtw88_8821ce` geladen und abgesichert. |
| **Erledigt** | **Fenster-Schatten & Transparenz haben komplett gefehlt** | Picom ist wegen eines Syntaxfehlers in der Konfiguration abgestürzt. | In der `~/.config/picom.conf` am Ende des `wintypes`-Blocks ein fehlendes Semikolon (;) ergänzt. |
| **Erledigt** | **Papirus-Ordner blieben blau statt violett** | Dem System fehlte das Anpassungs-Skript und die Syntax hatte sich geändert. | Skript installiert und Ordnerfarbe mit `papirus-folders -t Papirus-Dark -C violet -u` umgestellt. |
| **Erledigt** | **System-Sprache & X11-Eingabemethode für Steam** | Locales fehlten auf OS-Ebene, was X11-Fehler (`XOpenIM() failed`) in Steam verursachte. | `dpkg-reconfigure locales` ausgeführt (`de_AT` & `en_US`) und Cache gesäubert. |
| ─── | ─────────────────────────────────────────── | ───────────────────────────────────────────────── | ──────────────────────────────────────── |
| ⏳ **In Arbeit** | **Steam-Freezes beim Workspace-Wechsel** | Dem neuen Minimalsystem fehlten die 64-Bit-Intel-Medientreiber und die Off-Screen-Rendering-Erweiterungen. | Pakete nachinstalliert (`intel-media-va-driver:amd64`, `libosmesa6`, etc.). *Test läuft aktuell nach Reboot.* |
| ⚠️ **To-Do** | **Fehlende Grafiktreiber & Bibliotheken prüfen** | Auf dem neuen Minimalsystem könnten im Vergleich zum alten PC noch weitere Bibliotheken fehlen. | *Vergleichs-Skript schreiben oder Paketlisten abgleichen, falls nach dem Grafik-Fix noch Ruckler auftreten.* |
| ⚠️ **To-Do** | **Unnötige / Doppelte Programme entfernen** | Systembereinigung (z. B. doppelte Terminals wie XTerm/UXTerm, falls Kitty genutzt wird), um das OS schlank zu halten. | *Paketliste durchgehen, Duplikate identifizieren und via `apt purge` entfernen.* |
| ⚠️ **To-Do** | **Bibata-Modern-Classic Cursor als Standard setzen** | System nutzt noch das helle Standard-Adwaita-Cursor-Theme von Debian. | Muss über `~/.icons/default/index.theme` und die X-Ressourcen erzwungen werden. |
| ⚠️ **To-Do** | **Darkmode für ALLE Anwendungen erzwingen** | Das System nutzt noch das helle Adwaita-Theme, wodurch Apps wie Thunar weiß strahlen. | Muss über die GTK-2.0- und GTK-3.0-Konfigurationen umgestellt werden. |
| ⚠️ **To-Do** | **Polybar für dieses Gerät anpassen** | Netzwerkschnittstellen, Akku-Module oder Monitor-Namen passen noch nicht zur Hardware. | Die `config.ini` der Polybar auf die lokalen Gerätenamen (`wlo1`, `BAT0` etc.) prüfen. |
| ⚠️ **To-Do** | **Bluetui lässt sich nicht korrekt installieren** | Die Installation schlägt auf dem Debian-Minimalsystem fehl oder bricht ab. | Abhängigkeiten prüfen (z.B. `bluez`, `libdbus-1-dev` oder Build-Tools) und Installations-Skript checken. |
