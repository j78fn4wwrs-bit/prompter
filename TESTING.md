# Prompter: iPhone test checklist

Build: `cd ~/prompter && git pull && xcodegen`, then Cmd+R on your iPhone.

1. [ ] App launches; create a new script, type text, go back: it's saved in the list.
2. [ ] Edit and delete a script; relaunch the app: changes persist.
3. [ ] Start prompting: 3-2-1 countdown, then smooth scrolling with the reading line.
4. [ ] Speed and font-size controls change scrolling/text live; pause/resume works.
5. [ ] Mirror mode flips the text horizontally.
6. [ ] Rotate to landscape: layout still works.
7. [ ] Pro features show the $9.99 upgrade sheet; price reads $9.99.
8. [ ] Buy Pro (Xcode test mode, free): Pro unlocks, sheet closes. Restore Purchases also works, both in the sheet and from the gear menu (top left) on the script list.
9. [ ] Camera recording: allow camera + mic, record while reading, video saves to Photos (allow access).
10. [ ] Bluetooth clicker / keyboard (space or arrows) controls scrolling.
11. [ ] Custom text/background colors and read-time estimate show up.
12. [ ] Airplane mode: everything except purchase still works.

Paste any red Xcode errors back to Nihar.
