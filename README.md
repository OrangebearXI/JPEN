# ENJP - Japanese to English Chat Translator for FFXI (Windower4)

**ENJP** is a Windower4 addon that detects Japanese text in Final Fantasy XI chat and translates it into English.  
It uses the [DeepL API](https://www.deepl.com/pro-api) for high-quality translations and can also fall back to an offline dictionary for common words.

---

## Features

- Detects Japanese messages from **say, shout, yell, party, tell, linkshell1, and linkshell2** chat modes.
- Automatically translates them into English using DeepL.
- Offline dictionary fallback for common FFXI terms (stored in `data/dict.tsv`).
- Displays translations in a customizable on-screen overlay.
- Adjustable font, size, position, background, and max lines.
- Filters out prohibited words from specific channels (optional).
- Minimal performance impact with queued translations.

---

## Requirements

- [Windower4](https://windower.net/)
- A [DeepL API Free or Pro key](https://www.deepl.com/pro-api) (free tier works fine)
- (Optional) `data/dict.tsv` file for offline translations

---

## Installation

1. Download or clone this repository into your `addons` folder in Windower4:
