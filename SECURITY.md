# Security and private data

The converter runs locally and makes no network requests. ffprobe reads only the selected recording's media, with a per-file timeout. Relative media paths and symlink targets must remain beneath the recording directory. Input event logs have a size limit. Existing outputs are never overwritten.

If you find a security issue, use GitHub's private vulnerability reporting if available, or contact the maintainer through their public profile to arrange a private report. Do not include recordings, credentials, or personal filesystem paths in a public issue.

Only the latest development version is maintained during alpha. Review contributions and dependencies before running them on private recordings.
