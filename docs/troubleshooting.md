# Troubleshooting

## The app says it cannot find the ISO or program files

Open the recording folder itself (the one containing the `.drp`, the `.mp4`, `Video ISO Files`, and `Audio Source Files`), not a parent folder or a copy that only has the `.drp`. The converter finds media relative to the `.drp`, so the subfolders must still be there. Renaming the folder is fine.

## "This Recording Has 2 Sessions"

In version 1.4 or later, choose the recording by its start time and duration. Convert it, then use **Change Session…** for the next one. Each has its own default XML filename and Final Cut event name. Older apps need an update; the command line selects a session with `--session 2`.

Keep the ATEM's numbered media names intact. Multi-session conversion checks embedded video timecodes and camera WAV Broadcast Wave references against the selected session. If a source cannot be confirmed, restore the original recording files rather than renaming another session's media to fit. A real two-session recording has passed import and XML round trips in Final Cut Pro 12.4; other naming conventions remain unverified.

## "Cannot find …" for a recording on a drive

The drive is not connected or has a different name. Connect the SSD and open the recording again, or choose it with **Open Recording…**.

## Final Cut shows the clips as offline

The XML references the files on the drive they were on when converted. Mount that drive, or move the recording folder and use File → Relink Files in Final Cut. Converting again after moving the folder also works.

## A camera shows "MP4 audio"

No WAV named like that camera's ISO file was found in `Audio Source Files`, so that angle uses the compressed audio inside the MP4. Check that the WAV was not moved or renamed.

## The Finder Quick Action shows "Can't get item 1 of «handler promptText»" (error -1728)

That is the 1.0.0 Quick Action. Install the current app instead; the Quick Action from a 1.1.0 or later release hands recordings to the app and has fixed dialogs.

## Something else

Run `python3 atem_iso_to_fcpxml.py "<folder>" --dry-run` and open an issue with the output after removing anything you do not want public. Never attach recordings, logs, generated XML, or libraries.
