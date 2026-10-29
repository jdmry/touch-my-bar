<h1 align="center">Touch My Bar</h1>

<p align="center">
  <b>Your Dock, your volume, your brightness — on the Touch Bar, in every app.</b>
</p>

![Touch My Bar on a MacBook Pro Touch Bar](docs/touch-bar.png)

The Touch Bar spends most of its life showing whatever the app in front
decided you needed. Touch My Bar takes it back and puts something there you'll
actually use: every app in your Dock, and the controls you reach for all day.

It doesn't change when you switch apps. It's just always there.

## Install

Touch My Bar installs with [Homebrew](https://brew.sh), the package manager
most Mac developers use. If you don't have it, paste this in Terminal first:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then:

```sh
brew tap jdmry/tap
brew trust jdmry/tap
brew install --cask touch-my-bar
xattr -dr com.apple.quarantine "/Applications/Touch My Bar.app"
```

Finally, turn on the Control Strip in **System Settings → Keyboard → Touch Bar
Settings**, and tap the icon on the right of your bar.

## Update

```sh
brew upgrade --cask touch-my-bar
xattr -dr com.apple.quarantine "/Applications/Touch My Bar.app"
```

The second line again, yes — a fresh download arrives freshly quarantined.

## What you get

**Your Dock, where your thumb already is.** The same apps, in the same order,
running or not. Tap to switch or launch — exactly what clicking the Dock does.
The icon pulses while an app starts up, so you know the tap landed.

**Volume and brightness that never move.** Pinned to the right, in every app,
in the same place every time. Hold to run them up or down. One button says
MUTE or UNMUTE, so you never have to work out which state you're in.

**A tap you can feel.** Optional haptic feedback and a click sound, because a
glass bar gives you nothing back on its own.

**Quit without reaching for the mouse.** Press and hold any app for its
actions — Quit, Hide, New Window.

**Out of your way.** Lives in the menu bar, starts at login, one tap to turn
off when you want the normal bar back.

## Requirements

A Mac with a Touch Bar (MacBook Pro 2016–2022) running macOS 13 or later.
Universal — Intel and Apple silicon.

## Before you install

Two of those commands aren't routine. They clear two separate gates, which is
why you need both.

**`brew trust`** is Homebrew's gate. It won't load a cask from someone else's
tap until you say you trust that tap. This one only lets Homebrew read the
install recipe.

**`xattr -dr com.apple.quarantine`** is Apple's gate. Anything downloaded gets
flagged, and macOS refuses to open flagged apps that Apple hasn't notarized.
Touch My Bar isn't notarized, so without this the app simply won't start —
clearing Homebrew's gate does nothing about Apple's.

Both come down to trusting a build Apple hasn't checked. That's a real ask,
which is why the source is all here — every line of it, for anyone who wants
to confirm there's nothing nasty inside.

---

[GPL-3.0](LICENSE) licensed — free to use and free to read, and anyone who
ships a modified version has to keep their source open too.

Built with Swift and AppKit. The code is commented throughout, including the
undocumented Apple interfaces it leans on and why each one is there.
