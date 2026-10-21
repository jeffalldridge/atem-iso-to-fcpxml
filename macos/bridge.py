"""Private JSON interface for the native app. Conversion stays in the CLI engine."""
import contextlib
import io
import json
import sys
from pathlib import Path

# In the app both files are in Resources; also support running from a checkout.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import atem_iso_to_fcpxml as converter


def handle(request):
    path = converter.locate_drp(Path(request['path']))
    if request['action'] == 'inspect':
        rec = converter.open_recording(path)
        plan = converter.make_plan(rec, extra_audio=[])
        selected = [a.source_index for a in plan.angles if a.kind == 'camera']
        cameras = [dict(id=i, name=s.name, used=i in selected,
                        wav=s.wav.name if s.wav else None)
                   for i, s in sorted(rec.sources.items()) if s.kind == 'Video' and s.mp4]
        audio = []
        for wav in rec.audio_files.values():
            label = wav.stem
            prefix = rec.name + ' '
            if label.startswith(prefix):
                label = label[len(prefix):]
            audio.append(dict(id=wav.name, name=label))
        main = next((a.audio.name for a in plan.angles if a.id == plan.main_audio_angle and a.audio), '')
        return dict(ok=True, recording=dict(path=str(path), name=rec.root.name,
                    output=str(path.with_suffix('.fcpxml')), cameras=cameras, audio=audio,
                    soundtrack=main, warnings=rec.warnings))
    if request['action'] != 'convert':
        raise ValueError('Unknown action')
    cameras = request['cameras']
    if not cameras:
        raise converter.ConversionError('Select at least one camera.')
    args = [str(path), '--cameras', ','.join(str(i) for i in cameras)]
    if request.get('soundtrack'):
        args += ['--audio', request['soundtrack']]
    extras = request.get('extras', [])
    if not extras:
        args += ['--no-extra-audio']
    for extra in extras:
        args += ['--extra-audio', extra]
    if request.get('replace') is True:
        args += ['--force']
    output = io.StringIO()
    with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
        status = converter.main(args)
    if status:
        return dict(ok=False, error=output.getvalue().strip())
    return dict(ok=True, output=str(path.with_suffix('.fcpxml')), report='\n'.join(line for line in output.getvalue().splitlines()
                    if line.startswith(('Timeline:', 'Warning:', '  '))))


if __name__ == '__main__':
    try:
        response = handle(json.load(sys.stdin))
    except Exception as exc:
        response = dict(ok=False, error=str(exc))
    print(json.dumps(response))
