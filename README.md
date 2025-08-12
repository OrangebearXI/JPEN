# ENJP - Japanese to English Chat Translator for FFXI (Windower4)

**ENJP** is a Windower4 addon that detects Japanese text in Final Fantasy XI chat and translates it into English.  
It uses the [DeepL API](https://www.deepl.com/pro-api) for high-quality translations and can also fall back to an offline dictionary for common words.

---

## Features

- Detects Japanese messages from **say, shout, yell, party, tell, linkshell1, and linkshell2** chat modes.
- Automatically translates them into English using DeepL.
- Offline dictionary fallback for common FFXI terms (stored in `data/dict.tsv`).
- **Incorporates the in-game prohibited term filter** to automatically skip translations containing blocked words.
- Customizable on-screen overlay: font, size, position, background, and number of lines.
- Adjustable max lines (default 10, can be set to any value).
- Optional channel-based filtering.
- Minimal performance impact with queued translations.

---

## Requirements

- A [DeepL API Free or Pro key](https://www.deepl.com/pro-api) (free tier works fine)
- (Optional) `data/dict.tsv` file for offline translations

---

## Installation

1. Download or clone this repository into your `addons` folder in Windower4:
2. Place your `dict.tsv` file into `addons/enjp/data/` if you want offline dictionary support.
3. In-game, load the addon:
//lua load enjp
4. Add your DeepL API key:
//enjp addkey YOUR_API_KEY

---

## Commands

| Command | Description |
|---------|-------------|
| `//enjp on` | Enable translations |
| `//enjp off` | Disable translations |
| `//enjp clear` | Clear the translation overlay |
| `//enjp addkey <key>` | Save your DeepL API key |
| `//enjp filter on/off` | Toggle prohibited term filtering |
| `//enjp addprohibited <folder>` | Set prohibited term file directory |
| `//enjp reloadfilter` | Reload prohibited term rules |
| `//enjp test [jp text]` | Test translation with sample Japanese text |
| `//enjp diag` | Check DeepL API status |
| `//enjp bg <name>` | Set background image from `resources/` folder |
| `//enjp bgpath <path>` | Set custom background image path |
| `//enjp bgalpha <0-255>` | Set background transparency |
| `//enjp dims` | Show current overlay box dimensions |
| `//enjp bgdiag` | Debug background settings |

---

## Settings

Settings are stored in `addons/enjp/data/settings.xml`.  
Key options include:

- `max_lines` – Maximum number of translated lines shown in overlay  
- `font` – Font name  
- `size` – Font size  
- `pos` – Overlay position (`x`, `y`)  
- `bg` – Background image path and alpha  
- `box_width`, `box_pad_x`, `box_pad_y` – Overlay box dimensions  

You can edit this file manually or change the defaults in the `enjp.lua` file.

---

## Example Usage

**Basic setup:**
//lua load enjp
//enjp addkey 12345678-abcd-efgh

**During gameplay:**
Japanese messages in supported channels will appear in English in an overlay.
Offline translations show with [Offline] before the text.
You can toggle the addon on/off anytime with //enjp on or //enjp off.


**Known Limitations**
-Requires a working internet connection for DeepL translations.
-Only translates Japanese → English (as coded now).
-Messages longer than DeepL’s free plan limit may fail to translate.
-Will not detect or translate messages outside the monitored channels.
