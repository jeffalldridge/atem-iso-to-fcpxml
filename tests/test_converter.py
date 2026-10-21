"""Synthetic tests: no private DRP, WAV, recording paths, or real media required."""
import copy
from fractions import Fraction as F
import json
from pathlib import Path
import tempfile
import struct
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

import atem_iso_to_fcpxml as c


def header(tc="10:00:00:00", mode="1080p60"):
    return dict(version=1, masterTimecode=tc, videoMode=mode,
                sources=[dict(_index_=i, name=f"Camera {i}", type="Video", file=f"Video ISO Files/Session CAM {i}.mp4", startTimecode=tc) for i in (1, 2, 3, 4)],
                mixEffectBlocks=[dict(_index_=0, onAir=True, source=1, transitionActive=False, fadeToBlack="Inactive", upstreamKeys=[])], downstreamKeys=[])


def event(tc, **changes):
    return dict(masterTimecode=tc, mixEffectBlocks=[dict(_index_=0, **changes)])


class TimingTests(unittest.TestCase):
    def test_exact_fractional_rate(self):
        self.assertEqual(c.video_mode("1080p5994")[2], F(60000, 1001))
        self.assertEqual(c.seconds(F(1001, 30000)), "1001/30000s")

    def test_drop_frame(self):
        self.assertEqual(c.timecode_frames("00:10:00;00", F(30000, 1001)), 17982)
        self.assertEqual(c.timecode_frames("00:01:00;04", F(60000, 1001)), 3600)
        with self.assertRaises(c.ConversionError): c.timecode_frames("00:01:00;00", F(30000, 1001))

    def test_invalid_timecode_and_interlace(self):
        for tc in ("24:00:00:00", "00:60:00:00", "00:00:00:60", "oops"):
            with self.assertRaises(c.ConversionError): c.timecode_frames(tc, F(60))
        with self.assertRaises(c.ConversionError): c.video_mode("1080i50")

    def test_midnight(self):
        rows = [header("23:59:59:00"), event("00:00:00:00", source=2), event("00:00:01:00", onAir=False)]
        segs = c.edit_segments(rows, F(60), 120)
        self.assertEqual([(s.offset, s.end, s.source) for s in segs], [(0,60,1),(60,120,2)])

    def test_out_of_order(self):
        with self.assertRaises(c.ConversionError):
            c.edit_segments([header(),event("10:00:00:30",source=2),event("10:00:00:20",source=1)], F(60), 120)

    def test_transition_fallback_preserves_exact_range(self):
        rows = [header(),event("10:00:00:30", transitionActive=True),event("10:00:01:00", transitionActive=False,source=2)]
        segments = c.edit_segments(rows,F(60),120)
        self.assertEqual([(s.offset,s.end,s.source) for s in segments],[(0,30,1),(30,60,None),(60,120,2)])

    def test_sparse_nested_state_does_not_erase_key(self):
        state = dict(mixEffectBlocks=[dict(_index_=0,source=1,upstreamKeys=[dict(_index_=0,onAir=True)])])
        c.merge_state(state, dict(mixEffectBlocks=[dict(_index_=0,source=2)]))
        self.assertTrue(state["mixEffectBlocks"][0]["upstreamKeys"][0]["onAir"])

    def test_end_duration_mismatch(self):
        with self.assertRaises(c.ConversionError): c.edit_segments([header(),event("10:00:00:30",onAir=False)],F(60),120)


class ConversionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="atem test & ")
        self.root = Path(self.tmp.name)
        self.drp = self.root / "Session.drp"
        self.rows = [header(),event("10:00:01:00",source=2),event("10:00:02:00",onAir=False)]
        self.save()
        (self.root / "Video ISO Files").mkdir()
        (self.root / "Audio Source Files").mkdir()
        for file in ["Session.mp4",*[f"Video ISO Files/Session CAM {i}.mp4" for i in (1,2,3,4)],
                     *[f"Audio Source Files/Session {source}.wav" for source in ("CAM 1","CAM 2","CAM 3","CAM 4","MIC 1","MIC 2")]]:
            p = self.root / file
            if p.suffix == ".wav":
                p.write_bytes(b"RIFF" + struct.pack("<I", 12) + b"WAVEdata" + struct.pack("<I", 0))
            else:
                p.touch()
        self.mock = patch.object(c, "probe", side_effect=self.probe)
        self.mock.start()

    def tearDown(self):
        self.mock.stop()
        self.tmp.cleanup()

    def save(self): self.drp.write_text("\n".join(json.dumps(x) for x in self.rows))

    def probe(self, path, executable):
        if path.suffix == ".wav":
            stream = dict(codec_type="audio",codec_name="pcm_s24le",channels=2,sample_rate="48000",duration_ts=96000,time_base="1/48000")
        else:
            stream = dict(codec_type="video",codec_name="h264",width=1920,height=1080,avg_frame_rate="60/1",duration_ts=120,time_base="1/60",tags=dict(timecode="10:00:00:00"))
        return dict(streams=[stream],format={})

    def test_multicam_uses_only_selected_inputs_and_pcm(self):
        data, report = c.convert(self.drp)
        x = ET.fromstring(data)
        self.assertEqual([a.get("angleID") for a in x.findall(".//multicam/mc-angle")],["cam1","cam2","audio0","audio1"])
        self.assertEqual(report["multicam_camera_inputs"], [1,2])
        self.assertEqual(report["soundtrack"], "Session CAM 1.wav")
        resources = {a.get("id"):a for a in x.findall("./resources/asset")}
        for asset in resources.values():
            if asset.get("name").endswith(".mp4"):
                self.assertIsNone(asset.get("hasAudio"))
            if asset.get("name").endswith(".wav"):
                self.assertEqual(asset.get("hasAudio"),"1")
                self.assertIsNone(asset.get("hasVideo"))
        project = x.find(".//project/sequence/spine")
        clips = project.findall("mc-clip")
        self.assertEqual([(n.get("offset"),n.get("start"),n.get("duration")) for n in clips],[("0s","0s","1s"),("1s","1s","1s")])
        sound = clips[0].find("asset-clip")
        self.assertEqual(sound.get("duration"),"2s")
        self.assertTrue(resources[sound.get("ref")].get("name").endswith("CAM 1.wav"))
        self.assertNotIn("CAM 3.mp4",data.decode())
        self.assertIn("%20",data.decode())
        self.assertIn("%26",data.decode())

    def test_camera_compounds_pair_matching_wav(self):
        data,_ = c.convert(self.drp)
        x = ET.fromstring(data)
        for i in (1,2):
            compound = x.find(f"./resources/media[@id='camera{i}']/sequence/spine/clip")
            self.assertIsNotNone(compound.find("video"))
            self.assertIsNone(compound.find("audio"))
            self.assertIsNone(compound.find("asset-clip").get("srcEnable"))
            self.assertEqual(compound.find("asset-clip").get("offset"),"36000s")

    def test_broadcast_wav_origin_survives_every_reference(self):
        for path in (self.root / "Audio Source Files").glob("*.wav"):
            bext = bytes(338) + struct.pack("<Q", 36000 * 48000) + bytes(256)
            chunks = b"bext" + struct.pack("<I", len(bext)) + bext + b"data" + struct.pack("<I", 0)
            path.write_bytes(b"RIFF" + struct.pack("<I", len(chunks)+4) + b"WAVE" + chunks)
        data, report = c.convert(self.drp)
        x = ET.fromstring(data)
        wav_ids = {m.get("id") for m in x.findall("./resources/asset") if m.get("hasAudio") == "1"}
        for node in x.iter():
            if node.get("id") in wav_ids or node.get("ref") in wav_ids:
                self.assertEqual(node.get("start"), "36000s")
        self.assertEqual(report["soundtrack_bwf_start"],"36000s")

    def test_can_include_unused_camera(self):
        data,report = c.convert(self.drp,cameras=[1,2,3],extra_audio=[])
        self.assertEqual(report["multicam_camera_inputs"],[1,2,3])
        self.assertNotIn("MIC 1.wav",data.decode())

    def test_cannot_omit_used_input(self):
        with self.assertRaises(c.ConversionError): c.convert(self.drp,cameras=[1])

    def test_mic_as_main_audio(self):
        data,report=c.convert(self.drp,audio="MIC 1")
        self.assertEqual(report["soundtrack"],"Session MIC 1.wav")
        self.assertIn(b'angleID="audio0" srcEnable="audio"',data)

    def test_missing_companion_wav_is_fatal(self):
        (self.root/"Audio Source Files/Session CAM 2.wav").unlink()
        with self.assertRaises(c.ConversionError): c.convert(self.drp)

    def test_renamed_recording_folder_ignores_stale_volume(self):
        self.rows[0]["sources"][0].update(volume="Old Disk",projectPath="Old Name")
        self.save()
        self.assertTrue(c.convert(self.drp)[0].startswith(b'<?xml'))

    def test_path_traversal_and_symlink_escape(self):
        with self.assertRaises(c.ConversionError): c.local_media(self.root,"../other.mp4")
        (self.root/"escape.mp4").symlink_to(self.root.parent/"other.mp4")
        with self.assertRaises(c.ConversionError): c.local_media(self.root,"escape.mp4")

    def test_selected_mic_symlink_cannot_escape_recording(self):
        mic = self.root / "Audio Source Files/Session MIC 1.wav"
        mic.unlink()
        mic.symlink_to(self.root.parent / "outside.wav")
        with self.assertRaises(c.ConversionError): c.convert(self.drp, audio="MIC 1")

    def test_resolve_archive_and_multiple_session_rejected(self):
        self.drp.write_bytes(b"PK\x03\x04")
        with self.assertRaises(c.ConversionError): c.load_drp(self.drp)
        self.rows.append(header());self.save()
        with self.assertRaises(c.ConversionError): c.load_drp(self.drp)

    def test_overwrite_refused_before_any_output(self):
        output = self.root / "out.fcpxml"
        output.write_text("keep")
        self.assertEqual(c.main([str(self.drp),"-o",str(output)]),2)
        self.assertEqual(output.read_text(),"keep")
        self.assertFalse(output.with_suffix(".conversion.json").exists())

    def test_unique_output_preserves_existing_xml(self):
        output = self.root / "Session.fcpxml"
        output.write_text("keep")
        with patch("shutil.which", return_value="ffprobe"):
            self.assertEqual(c.main([str(self.drp), "--unique-output"]), 0)
        self.assertEqual(output.read_text(), "keep")
        self.assertTrue((self.root / "Session (2).fcpxml").is_file())

    def test_short_audio_rejected(self):
        original=self.probe
        def short(path,exe):
            result=original(path,exe)
            if path.suffix==".wav": result["streams"][0]["duration_ts"]=48000
            return result
        with patch.object(c,"probe",side_effect=short):
            with self.assertRaises(c.ConversionError): c.convert(self.drp)


if __name__ == "__main__": unittest.main()
