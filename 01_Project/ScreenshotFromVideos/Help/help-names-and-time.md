# Timestamps and Filenames

Both options live under **Options** in the right-hand panel. Click **Options…** to show their settings.

## Burning in a timestamp

Turn on **Burn timestamp into image** to print each frame's time onto the image itself, so the position in the video stays visible wherever the picture ends up.

- **Timestamp position** — pick one of the four corners.
- **Font size** — set as a percentage of the image height, so it looks the same at any resolution.

The player shows a live preview of the timestamp in the chosen corner before you export.

## Filenames

With **Number filenames sequentially** turned off, each file is named after its time in the video, such as `01-23.456.png` for 1 minute 23.456 seconds (videos over an hour add the hours in front).

Turn it on to use the **Filename pattern** instead. The default is `{name}_{timecode}`. Click the token buttons under the field to add them to the end of the pattern:

| Token | Becomes |
|---|---|
| `{name}` | The video's filename |
| `{counter}` | A zero-padded counter: 0001, 0002, … |
| `{index}` | A plain counter: 1, 2, 3, … |
| `{timecode}` | The frame's timecode, such as `00-01-23-15` |
| `{frame}` | The frame's number in the video |
| `{seconds}` | The frame's time, such as `00-01-23-456` |
| `{date}` | Today's date, YYYY-MM-DD |
| `{time}` | The current time, HH-MM-SS |

Files are numbered in time order, so they always sort correctly in Finder.

## Existing files are never overwritten

If a file with the same name already exists in the output folder, the new one gets `_1`, `_2` and so on added to its name.
