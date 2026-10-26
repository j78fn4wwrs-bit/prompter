# Steady Prompter: iPhone test checklist

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

## iPad checks (universal app)
Build on the iPad the same way (`git pull && xcodegen`, pick the iPad, Cmd+R).

13. [ ] Script list and editor show side by side (list left, editor right) in landscape; portrait still works. Tap + : the new script opens on the right.
14. [ ] Rotate through all four orientations (including upside-down): list, editor and prompter all re-lay out.
15. [ ] Split View and Slide Over: open Safari next to Prompter. Prompter text and the reading line shrink to fit at 1/3, 1/2 and 2/3 widths and grow again full screen.
16. [ ] Full screen prompter text is clearly bigger than on iPhone at the same slider setting; the controls panel stays a readable width.
17. [ ] Mirror mode flips the text on iPad.
18. [ ] Camera (Pro), landscape: the front-camera preview is level (not sideways) in both landscape directions and portrait; the saved video in Photos is upright.
19. [ ] Camera in Split View: on iPads without multitasking camera access you see "The camera pauses in Split View or Slide Over…" and nothing crashes; going full screen brings the preview back.
20. [ ] Bluetooth keyboard: space/return = play/pause, arrows and Page Up/Down = jump, Esc = close. A clicker (sends arrows/page keys) does the same.
21. [ ] Restore: on the iPad, gear menu > Restore Purchase with the same Apple Account unlocks Pro (one purchase covers iPhone and iPad). In Xcode test mode each device has its own test purchases, so this is a real check only with TestFlight/sandbox.

## App Store iPad screenshots (13-inch)
Apple requires 13-inch iPad screenshots (2064 × 2752 portrait or 2752 × 2064 landscape). Easiest:
1. Xcode > pick **iPad Pro 13-inch (M4)** simulator > Cmd+R.
2. Set up each screen (script list + editor, prompter running, mirror on), then **File > Save Screen** (Cmd+S) in the Simulator. Files land on the Desktop at the right size.
3. Camera doesn't work in the Simulator; take the recording screenshot on a real iPad or skip it.

## Script import (Text, RTF, PDF, Word, Pages)
Tap + > **Import File**. The title should be the file name; errors show in an alert.

22. [ ] **.txt** (UTF-8): imports exactly. Also try a UTF-16 file (TextEdit > Save > Plain Text, Encoding UTF-16) and a Windows/Notepad file with curly quotes: no garbled characters.
23. [ ] **.rtf** (TextEdit default format): text imports, formatting dropped.
24. [ ] **PDF** with real text (e.g. Pages > Export > PDF): all pages import, in order. A scanned/image-only PDF shows the "no selectable text" message.
25. [ ] **Word .docx**: paragraphs come in on separate lines; tabs and line breaks kept.
26. [ ] **Old Word .doc**: shows the "save as .docx" message (doesn't crash or import garbage).
27. [ ] **Pages**: a normal .pages file imports its text (from Pages' built-in preview). If it shows "Export from Pages as PDF, Word, or plain text, then import", that's expected for files saved without a preview.
28. [ ] **iCloud file not downloaded yet** (cloud icon in Files): picking it downloads and imports it.
29. [ ] **Real iPad/iPhone, Mac drive**: put scripts in iCloud Drive or a shared folder from the Mac (Files > Browse > Locations, or Connect to Server), pick one, imports.
30. [ ] **Real iPad, USB drive / SD card**: plug it in, picker > Browse > Locations > the drive name, pick a .txt, .pdf and .docx. All import; unplugging afterwards doesn't affect the imported script.
31. [ ] Third-party providers (Dropbox, Google Drive app) under Locations: pick a file, imports.
32. [ ] **iPad + menu, portrait and landscape**: with something on the clipboard, tap + > Import File. The Files picker opens (no new script, no clipboard alert). Cancel. Rotate, collapse/show the sidebar, repeat. Then + > Paste from Clipboard creates a script; with an empty clipboard it shows "Nothing to Paste" (never titled Import).

**Simulator note:** the iOS Simulator's file picker can't see your Mac's drives. That's Apple's limit, not the app's. To test there, drag a file from Finder onto the Simulator window (it lands in Files) and then import it. To test real drives, use the iPhone/iPad: Files > Locations > USB drive.

## Round 3 fixes (Oct 20): text size, drag & drop, paste, paywall, shortcuts, chapters
**Simulator setup first:** in the Simulator menu turn on **Edit > Automatically Sync Pasteboard**, otherwise Cmd-C on the Mac never reaches the app. For Pro screens without buying, use the gear menu (top left) > **Unlock Pro for testing** (debug builds only; it never ships). Real test purchases also work for free: the scheme uses `Products.storekit`.

33. [ ] **Text size slider:** small A on the left, big A on the right. Dragging right makes text BIGGER all the way to the end; text always wraps inside the screen and never goes blank. iPad range ≈ 24–120 pt, iPhone ≈ 20–80 pt. Close and reopen: the size is kept.
34. [ ] **Text size mid-script:** scroll halfway, change size: you stay roughly at the same place.
35. [ ] **Drag a .txt from the Mac Desktop onto the script list/sidebar:** a NEW script appears titled with the file name. The script that was open is unchanged.
36. [ ] **Drag a .txt, .pdf, .docx onto the open editor:** each creates a new script; the open script's text and title are NOT changed.
37. [ ] **Drag a file onto the empty "Pick a script" area** (iPad, nothing selected): new script.
38. [ ] **Drag a selected text snippet** (e.g. from Notes in Split View) onto the editor: it's inserted at the cursor (no new script).
39. [ ] **Paste:** copy text on the Mac, + > Paste from Clipboard: new script with that text. Allow the iOS "Paste" prompt if shown. Copy rich text (from TextEdit/Pages) also works. Empty clipboard shows "Nothing to Paste" with the Simulator tip.
40. [ ] **⌘V on the script list** (nothing open) creates a script from the clipboard; **⌘⇧V** does it any time. ⌘V inside the editor still pastes into the text normally.
41. [ ] **Paywall reasons (Pro locked):** Camera button opens a sheet headed with a camera icon and "Record yourself with the camera is a Pro feature". Read time opens "Read-time estimates are Pro".
42. [ ] **Colors (free):** the palette button opens Colors with free presets (White on Black, Black on White, Yellow on Black) that apply right away. "Pick any text and background color" (locked) opens the paywall headed "Custom colors are Pro". With Pro, the color pickers show.
43. [ ] **Debug unlock:** gear > Unlock Pro for testing ON: lock icons disappear, camera/custom colors/keyboard work. OFF again: locked.
44. [ ] **Keyboard (Pro on, hardware keyboard / Mac keyboard in Simulator; click the prompter once if keys do nothing):**
  - Space: play/pause. ↑/↓: speed up/down with a "Speed 3.5" toast.
  - ⌘+ (or ⌘=) / ⌘−: text bigger/smaller with a "Text 52 pt" toast.
  - M: "Marker N added"; an orange bar appears beside that line.
  - ←/→ and [ / ]: previous/next chapter or marker (smooth scroll; keeps playing if playing).
  - 1–9: jump to item N in the chapters list. Home or ⌘↑: back to top. Esc: exit.
  - ⌘/ (or ?): shortcuts help sheet. On iPad, holding ⌘ shows the system list with Bigger/Smaller Text, Back to Top, Keyboard Shortcuts.
  - With Pro off, a key shows "Keyboard control is a Pro feature" (Esc and ⌘/ still work).
45. [ ] **Chapters:** in the editor type lines like `# Intro` and `## Part 2`. The word-count row shows "· 2 chapters". In the prompter they show bold orange without the #.
46. [ ] **Chapters list:** the list button (top right in the prompter) shows Top, headings and markers with numbers 1–9. Tapping one scrolls smoothly there. Swipe a marker to delete it.
47. [ ] **Markers persist:** add markers, exit, relaunch the app: they're still there. Old scripts from before this update open fine (no data loss).
48. [ ] **Bookmark button** (top right, when paused) adds a marker at the reading line, same as M.

## v1.1 Remote control (two real devices)

The Simulator can't really test this (Multipeer between simulators is unreliable), so use two physical devices on the same Wi-Fi, e.g. your iPad as the prompter and your iPhone as the remote. Take it slow; one short session is plenty.

49. [ ] **Remote button:** on the script list, the remote icon (top right) opens Remote Control, free, no paywall. The screen stays awake while it's open.
50. [ ] **Allow Remote (Pro):** on the prompter device, open a script. With Pro off, the Remote button in the bottom panel shows a lock and opens "Remote control of this prompter is Pro". With Pro on (gear > Unlock Pro for testing), tap Remote, then turn on Allow Remote in the popover: a "Waiting" pill and "Remote code 1234" appear top left.
51. [ ] **Local network prompt:** the first time on each device, iOS asks to use the local network. Tap Allow. (If you tapped Don't Allow: Settings > Steady Prompter > Local Network.)
52. [ ] **Pair:** on the remote, the prompter's device name shows under Nearby prompters. Tap it, type the code, Connect. Both show "Connected". A wrong code shows a friendly error.
53. [ ] **Buttons:** Play/Pause (3-2-1 countdown on the prompter), Slower/Faster (speed toast), Back/Forward (chapters or markers; on a script without any, about one screen), Back to Top. The remote shows Playing/Paused, speed and the current chapter.
54. [ ] **Link drops:** while playing, turn Wi-Fi off on the remote. The prompter keeps scrolling and shows "Disconnected". Turn Wi-Fi back on with the Remote screen open: it reconnects by itself, no code needed.
55. [ ] **Remembered:** close and reopen Remote Control and the prompter: it reconnects on its own. "Forget paired prompter" makes it ask for the code again.
56. [ ] **Forget on the prompter:** after pairing, the prompter's bottom panel (paused) shows a red "Forget paired remote" button under the icon row. Tap it: the button disappears, the remote shows "Disconnected", the prompter shows a new code, and the remote must type that new code to reconnect. Also: turning Allow Remote off forgets the remote; turning it back on, the remote needs the code again.

## v1.1 Lens Glass buttons (D1)

Check each on iPhone, iPad and Mac (My Mac (Designed for iPad)), once in Light and once in Dark mode (Settings > Display & Brightness, or System Settings > Appearance on the Mac). Labels never wrap or clip.

57. [ ] **Remote screen look:** on the remote, pair and connect. Title reads "Remote". Navy/white gradient background, device name in big bold, a yellow PAUSED/PLAYING chip, "Speed 3.0" with a gauge icon, and a faint lens ring behind the header.
58. [ ] **Remote buttons:** a big yellow glowing Play (turns into Pause while playing), navy glass Slower/Faster and Back/Forward with yellow icons and text, and a darker Back to Top. Each press shrinks slightly, darkens and gives a tap haptic, and each still does what it did before (step 53). On the smallest iPhone everything fits without scrolling.
59. [ ] **Prompter control bar:** open a script, paused. The bottom bar is a rounded card (white in Light, dark navy in Dark) with round Back / yellow Play / Forward, minus and plus speed buttons around a yellow speed slider with the value (e.g. "3.0") on the right, the text-size slider, Mirror, Camera, Colors, and a "Remote" capsule. Back/Forward jump to the previous/next chapter or marker; minus/plus change speed with the "Speed" toast. On iPhone the transport and speed rows stack.
60. [ ] **Remote popover:** with Pro on, tap Remote: a popover opens with an Allow Remote switch (yellow when on), a line with the device name and the pairing code, and Done. Switch on: the Waiting pill and code appear. Pair the phone: the Remote capsule gets a yellow ring and glow while connected. Switch off: the remote is forgotten (same as step 56). Done closes the popover.
61. [ ] **Accessibility:** with VoiceOver on, the buttons read "Back", "Play", "Forward", "Slower", "Faster", "Speed", "Text size", "Remote, Allow Remote: on/off", and the switch reads "Allow Remote, On/Off". With Pro off, the Remote capsule shows a lock and still opens the paywall.

## v1.1 Branded look across the app (D1)

Check each on iPhone, iPad and Mac (Designed for iPad), in Light and Dark mode. Also try a large text size (Settings > Accessibility > Display & Text Size > Larger Text): text grows and nothing is cut off.

62. [ ] **Script list:** pale-blue (Light) / navy (Dark) gradient behind the list, each script in a card row with a small navy glass tile, title and "N words · date". Tint (selection, toolbar icons) is navy in Light and yellow in Dark. The toolbar shows the gear, a remote icon (phone with waves) and a filled + button; all still work. Swipe to delete still works.
63. [ ] **Empty states:** delete all scripts: "No scripts yet" with a glass tile and faint lens ring. On iPad/Mac with no script selected: "Pick a script" in the same style. Dropping a file on either still creates a script.
64. [ ] **Editor:** title in bold, then yellow chips "N words" and (if any) "N chapters", then the Read time button. Type `# Intro` on a line: that line turns bold and navy (Light) / yellow (Dark) right away; `#Intro` (no space) stays plain. Typing, cursor position, undo and drag-and-drop work as before, and the prompter still shows the chapter.
65. [ ] **Settings (gear menu) and alerts:** the menu, Restore Purchase alert, "Nothing to Paste" and "Couldn't Import File" alerts use the brand tint and read clearly in both modes.
66. [ ] **Paywall:** gradient background with a card, glass icon tiles for the header and each feature. "Unlock Pro for $9.99" is a big yellow glass button with dark text, readable in both modes; it dims while busy. Restore Purchase, Privacy Policy and Terms links work. After unlocking, "Pro is unlocked" shows in green.
67. [ ] **Remote pairing list (iPhone):** gradient background, card rows, glass tile next to each nearby prompter, "Paired"/"Reconnecting…" text readable. Code entry alert and "Forget paired prompter" work as before.
68. [ ] **Prompter sheets:** Colors, Chapters & Markers and Keyboard Shortcuts sheets show the gradient background behind their rows, in both modes.
69. [ ] Prompter with a keyboard (Pro): add 2–3 markers with M. Tab jumps to the next marker, Shift-Tab to the previous one. Chapters (#) are skipped. With no markers, Tab shows "No markers yet". At the last marker it shows "Last marker"; Shift-Tab before the first goes to the top. The ⌘/ help lists Tab / Shift-Tab.

## v1.1 Markers from more places

70. [ ] **Editor Add Marker:** open a script in the editor, tap inside a line in the middle of the text, then tap the navy glass "Add Marker" pill next to the word/chapter chips. A "Name Marker" alert opens pre-filled with "Marker N". Save it. A yellow "N markers" chip appears. Tap Add Marker again on the same line: "Already marked" shows briefly and nothing is added.
71. [ ] **Editor marker in prompter:** press Start. The marked line has the marker bar, it is listed in Chapters & Markers under your name, and Tab (Pro keyboard) jumps to it.
72. [ ] **Control panel Marker button:** in the prompter, paused, the bottom panel has a bookmark button right after Mirror, Camera and Colors. Tap it: "Marker N added" shows and the Name Marker alert opens. It does exactly what the top bookmark button and M do.
73. [ ] **Naming while prompting:** while playing, press M (or tap a marker from the remote flow): the marker is added with the toast only, no alert interrupts the read. Paused, M opens the name alert. Cancel keeps the default "Marker N".
74. [ ] **Rename from the list:** in Chapters & Markers, long-press (or right-click on Mac) a marker: Rename and Delete. Swipe left on a marker: Delete and Rename. Rename changes the title in the list. Clearing the name brings back "Marker N: first words".
75. [ ] **Upgrade data:** a script that had markers from an earlier build still opens with its markers, shown as "Marker N: …" (no crash, no lost markers).
76. [ ] **Top buttons contrast:** with Black on White (and any light custom background), the five round buttons at the top right (close, keyboard, list, bookmark, back to top) are dark icons on a light grey circle and clearly visible. On White on Black or with the camera on, they are white icons on a faint circle.
