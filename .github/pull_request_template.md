**What changes for the user?**

**Evidence**
<!-- A test, a log excerpt, or a Final Cut round trip. Say what you ran, and what you did not. -->

**Checklist**
- [ ] `swift test`
- [ ] `python3 -m unittest discover -s tests -v`
- [ ] `python3 scripts/build_quick_action.py --check` (and rebuilt if `atem_iso_to_fcpxml.py` changed)
- [ ] Python and Swift still write identical XML (behavior changed in the Python file first)
- [ ] A Final Cut round trip, recorded in `docs/validation.md`, if the XML the converter writes changed
- [ ] No recordings, `.drp` files, generated XML, or personal paths in the diff
