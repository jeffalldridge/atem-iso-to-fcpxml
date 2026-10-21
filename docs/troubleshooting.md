# Troubleshooting

## Finder reports a promptText error (-1728)

The 1.0.0 Quick Action tries to read an AppleScript handler as a list. The error appears before camera selection: `Can't get item 1 of «handler promptText»`.

The fix is in the 1.0.1 source. The workflow embeds the converter, so pulling source changes does not update an installed Quick Action. From an updated checkout, run:

```sh
python3 scripts/build_quick_action.py --install
```

Dismiss the failed action and start a new one from Finder. Do not reinstall the 1.0.0 release ZIP; it contains the old code. Once a newer release is available, install its workflow and replace the existing copy.

To inspect the installed version:

```sh
grep '__version__ =' "$HOME/Library/Services/ATEM ISO to FCPXML.workflow/Contents/document.wflow"
```

If the error persists with 1.0.1, check whether you opened an older downloaded workflow in Automator rather than the installed Finder action. Report the installed version and error text, without recordings or generated XML.

## Validation scope

The dialog's argument handling and returned selections have synthetic regression coverage. Compilation and unit tests do not establish that every Finder dialog path works. Before publishing the patch, exercise camera selection, soundtrack selection, no extra audio, cancellation, and output replacement through Finder. See [the release checklist](releasing.md).
