# JPEN, Japanese to English chat translator for FFXI (Windower4)

JPEN is a Windower4 addon for Final Fantasy XI. It watches chat, detects Japanese, and shows an English translation in a small overlay. DeepL powers the translations. If DeepL is unavailable, JPEN can fall back to a local dictionary for common game terms.

---

## What it does
- Listens to **Say, Shout, Yell, Party, Tell, Linkshell1, Linkshell2**.
- Sends Japanese text to DeepL, then displays the English result in an overlay.
- Falls back to a local dictionary at `data/dict.tsv` if the API fails.
- Respects your in game prohibited term list. Lines containing blocked words are skipped.
- Customisable overlay, font, size, background image, position, and number of lines.
- Batches requests and caches results to keep CPU and bandwidth low.

---

## Requirements
- A DeepL API key, Free or Pro both work: https://www.deepl.com/pro-api
- Optional, `data/dict.tsv` for offline fallback. Two columns, tab separated, JP then EN.

---

## Install
1. Copy this repository to `Windower4/addons/JPEN`.
2. Optional, put your `dict.tsv` in `addons/JPEN/data/`.
3. In game, load the addon:
   ```
   /lua load jpen
   ```
4. Add your DeepL key:
   ```
   /jpen addkey YOUR_API_KEY
   ```
That is it. When someone speaks Japanese in a supported channel, an English line appears in the overlay.

---

## Quick commands
```
/jpen on                      Enable translations
/jpen off                     Disable translations
/jpen clear                   Clear the overlay
/jpen addkey XXXX-XXXX        Save your DeepL API key
/jpen test こんにちは           Send a test line through the pipeline
```

---

## All commands, with examples

| Command                         | What it does                                                                                 | Example                                                                |
|---------------------------------|----------------------------------------------------------------------------------------------|------------------------------------------------------------------------|
| `//jpen on`                     | Enable translations.                                                                         | `//jpen on`                                                            |
| `//jpen off`                    | Disable translations and hide the overlay.                                                   | `//jpen off`                                                           |
| `//jpen clear`                  | Clear all lines from the overlay.                                                            | `//jpen clear`                                                         |
| `//jpen addkey <key>`           | Save your DeepL API key.                                                                     | `//jpen addkey 1234-ABCD...`                                           |
| `//jpen filter on`              | Apply your in game prohibited term rules.                                                    | `//jpen filter on`                                                     |
| `//jpen filter off`             | Ignore prohibited term rules.                                                                | `//jpen filter off`                                                    |
| `//jpen addprohibited <folder>` | Set the folder that contains your prohibited term files.                                     | `//jpen addprohibited C:\PlayOnline\SquareEnix\FINAL FANTASY XI\USER` |
| `//jpen reloadfilter`           | Reload prohibited term rules from disk.                                                      | `//jpen reloadfilter`                                                  |
| `//jpen test [jp]`              | Send a sample Japanese line to test the overlay and pipeline.                                | `//jpen test 今日はありがとう`                                          |
| `//jpen bg <name>`              | Use an image from the addon `Resources` folder. Extension is optional.                       | `//jpen bg bg4`                                                        |
| `//jpen bgpath <full path>`     | Use a custom background image from any path.                                                 | `//jpen bgpath D:\pics\chat_bg.png`                                    |
| `//jpen bgalpha <0-255>`        | Set background transparency. 0 is invisible, 255 is opaque.                                  | `//jpen bgalpha 220`                                                   |
| `//jpen max <n>`                | Set how many translated lines to keep in the overlay.                                        | `//jpen max 7`                                                         |
| `//jpen pad <n>`                | Add extra pixels under the last line for breathing room.                                     | `//jpen pad 6`                                                         |
| `//jpen dims`                   | Print the current anchor and measured height for debugging.                                  | `//jpen dims`                                                          |

---

## Settings

Settings live in `addons/JPEN/data/settings.xml`. You can edit them by hand or set them once with commands.

- `enabled`, master switch, true or false.
- `max_lines`, how many translated lines to keep in the box.
- `font`, font name.
- `size`, font size in pixels.
- `line_gap`, extra pixels between lines.
- `pos`, overlay anchor position, `x` and `y`.
- `box_width`, width of the overlay in pixels.
- `box_pad_x`, left and right padding in pixels.
- `box_pad_y`, top padding in pixels.
- `overscan_y`, extra space under the last line, bottom only.
- `bg.enabled`, show the background image, true or false.
- `bg.path`, file path to the background image.
- `bg.alpha`, 0 to 255, background opacity.
- `filter_enabled`, use the in game prohibited term rules, true or false.

---

## Background images

Place images in `addons/JPEN/Resources`.

Pick one by name:
```
/jpen bg bg4
```
Or set a full path:
```
/jpen bgpath C:\Users\YOURNAME\Windower\addons\JPEN\Resources\bg4.png
```

---

## How translations work

1. JPEN expands auto translate tokens, then checks the line for Japanese characters.
2. If Japanese is present, JPEN sends the line to DeepL.
3. If DeepL returns a result, JPEN shows the English text.
4. If DeepL fails, JPEN looks up the exact line in `data/dict.tsv`. If a match exists, it shows that with `[Offline]` at the start.
5. Prohibited terms, if enabled, are checked before any translation happens.
6. DeepL is always tried first. The local dictionary is only used on failure.

---

## Performance

- Lines are batched, so a burst of chat triggers one network call, not many.
- Recent lines are cached to avoid re translating duplicates.
- The overlay redraws only when text changes or you move it.

---

## Troubleshooting

- **Nothing shows.** Turn it on, `//jpen on`, then try `//jpen test こんにちは`.
- **Still nothing.** Add your key again, `//jpen addkey <key>`.
- **No background.** Set one with `//jpen bg bg4` or `//jpen bgpath <file>`.
- **Box feels tight at the bottom.** Increase padding, `//jpen pad 6` or higher.
- **Expected lines are missing.** Try `//jpen filter off` to rule out the prohibited term rules.

---

## Known limitations

- Internet is required for DeepL results.
- Current direction is Japanese to English.
- Very long messages may exceed DeepL Free limits.
- Only the listed chat channels are translated.

---

## Credit

Created by **Orangebear**. Thanks to the Windower team and the DeepL API.
