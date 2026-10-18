# Prompter (placeholder name)

An honest teleprompter for iPhone. SwiftUI + SwiftData, iOS 18+. No accounts, no analytics, no backend.

- **Free:** unlimited scripts (write, paste, import .txt), smooth auto-scroll, speed + font size, mirror, tap to play/pause, 3-2-1 countdown, reading line, screen stays awake.
- **Pro ($9.99 one-time, `com.mikejohnson.prompter.pro`):** front-camera recording saved to Photos, keyboard/clicker control, custom colors, read time.

## Run it on your iPhone (Mike)

```bash
cd ~
git clone https://github.com/j78fn4wwrs-bit/prompter.git
cd prompter
xcodegen
open Prompter.xcodeproj
```

1. In Xcode, select the **Prompter** target → **Signing & Capabilities** → set **Team** to your Apple ID / developer team.
2. Plug in your iPhone (Developer Mode on), pick it as the run destination at the top.
3. Press **Cmd+R**.

To update later: `cd ~/prompter && git pull && xcodegen`, then Cmd+R.

Testing Pro: running from Xcode uses `Products.storekit`, so the $9.99 purchase is free and fake. Reset it in Xcode via **Debug → StoreKit → Manage Transactions**.
