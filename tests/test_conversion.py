"""End-to-end filesystem safety and completion tests, using real ffmpeg audio."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
import wave

SCRIPT = Path(__file__).resolve().parents[1] / 'wav-to-flac.sh'
FFMPEG = shutil.which('ffmpeg')
BASH = os.environ.get('TEST_BASH', '/bin/bash')


class ConversionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.music = self.root / 'music'
        self.music.mkdir()
        (self.music / '#recycle').mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), REAL_FFMPEG=FFMPEG,
                        PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        JOB_STATE=str(self.root / 'jobs.json'))
        self.write_exe('nproc', '#!/bin/sh\nprintf "2\\n"\n')

    def write_exe(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def wav(self, name='track.wav', value=0):
        path = self.music / name
        with wave.open(str(path), 'wb') as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(8000)
            stream.writeframes(value.to_bytes(2, 'little', signed=True) * 8000)
        return path

    def run_script(self, *flags):
        return subprocess.run([BASH, str(SCRIPT), *flags, str(self.music)],
                              env=self.env, text=True, capture_output=True, timeout=30)

    def install_slow_encoder(self):
        self.write_exe('ffmpeg', '''#!/usr/bin/env python3
import fcntl, json, os, subprocess, sys, time
from pathlib import Path
args = sys.argv[1:]
if '-c:a' in args and args[args.index('-c:a') + 1] == 'flac':
    state = Path(os.environ['JOB_STATE'])
    def update(delta):
        with open(str(state) + '.lock', 'a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            data = json.loads(state.read_text()) if state.exists() else {'active':0,'peak':0,'done':0}
            data['active'] += delta
            data['peak'] = max(data['peak'], data['active'])
            if delta < 0: data['done'] += 1
            state.write_text(json.dumps(data))
    update(1)
    time.sleep(0.25)
    result = subprocess.run([os.environ['REAL_FFMPEG'], *args])
    update(-1)
    print('ENCODER_FINISHED', flush=True)
    sys.exit(result.returncode)
os.execv(os.environ['REAL_FFMPEG'], [os.environ['REAL_FFMPEG'], *args])
''')

    def test_completion_waits_for_single_exact_and_partial_batches(self):
        self.install_slow_encoder()
        for count in (1, 2, 3):
            with self.subTest(count=count):
                files = [self.wav(f'{count}-{index}.wav') for index in range(count)]
                state = Path(self.env['JOB_STATE'])
                state.unlink(missing_ok=True)
                process = subprocess.Popen([BASH, str(SCRIPT), '-n', str(self.music)],
                                           env=self.env, text=True, stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT, start_new_session=True)
                def cleanup(p=process):
                    try:
                        os.killpg(p.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    p.wait()
                    p.stdout.close()
                self.addCleanup(cleanup)
                output = []
                for line in process.stdout:
                    output.append(line)
                    if 'Conversion process completed' in line:
                        self.assertTrue(all(not path.exists() for path in files), ''.join(output))
                        self.assertEqual(json.loads(state.read_text())['done'], count)
                process.stdout.close()
                self.assertEqual(process.wait(timeout=10), 0, ''.join(output))
                data = json.loads(state.read_text())
                self.assertEqual(data['done'], count)
                self.assertEqual(data['active'], 0)
                self.assertLessEqual(data['peak'], 2)
                self.assertFalse(list(self.music.glob('*.tmp.*')))

    def test_truncated_existing_flac_never_trashes_source(self):
        source = self.wav()
        output = Path(str(source) + '.flac')
        output.write_bytes(b'fLaC' + b'broken' * 3)
        result = self.run_script('-n')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(source.exists())
        self.assertEqual(output.read_bytes(), b'fLaC' + b'broken' * 3)
        self.assertNotIn('Conversion process completed', result.stdout)

    def test_valid_but_different_flac_never_trashes_source(self):
        source = self.wav()
        other = self.wav('other.wav', 100)
        subprocess.run([FFMPEG, '-loglevel', 'error', '-i', str(other), str(source) + '.flac'], check=True)
        other.unlink()
        result = self.run_script('-n')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(source.exists())

    def test_failed_encoder_does_not_publish_partial_and_returns_failure(self):
        source = self.wav()
        self.write_exe('ffmpeg', '#!/bin/sh\nfor last; do :; done\nprintf partial > "$last"\nexit 7\n')
        result = self.run_script('-n')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(source.exists())
        self.assertFalse(Path(str(source) + '.flac').exists())
        self.assertFalse(list(self.music.glob('*.tmp.*')))
        self.assertNotIn('Conversion process completed', result.stdout)

    def test_dry_run_keeps_source_and_no_new_final_output(self):
        source = self.wav('spaces and\nnewline.wav')
        os.utime(source, (1600000000, 1600000000))
        result = self.run_script('-j', '1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(source.exists())
        self.assertEqual(source.stat().st_mtime, 1600000000)
        self.assertFalse(Path(str(source) + '.flac').exists())
        self.assertFalse(list(self.music.glob('*.tmp.*')))

    def test_real_run_publishes_verified_output_with_timestamp(self):
        source = self.wav()
        os.utime(source, (1600000000, 1600000000))
        result = self.run_script('-n', '-j', '1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = Path(str(source) + '.flac')
        self.assertTrue(output.exists())
        self.assertEqual(output.stat().st_mtime, 1600000000)
        self.assertTrue((self.music / '#recycle' / source.name).exists())
        self.assertFalse(source.exists())

    def test_existing_valid_flac_is_verified_and_preserved(self):
        source = self.wav()
        output = Path(str(source) + '.flac')
        subprocess.run([FFMPEG, '-loglevel', 'error', '-i', str(source), str(output)], check=True)
        before = output.read_bytes()
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(output.read_bytes(), before)
        self.assertTrue(source.exists())

    def test_trash_collision_preserves_both_originals(self):
        source = self.wav()
        destination = self.music / '#recycle' / source.name
        destination.write_bytes(b'previous original')
        result = self.run_script('-n')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(source.exists())
        self.assertEqual(destination.read_bytes(), b'previous original')

    def test_failure_in_first_worker_is_not_hidden_by_last_success(self):
        self.wav('bad.wav')
        good = self.wav('good.wav')
        self.write_exe('ffmpeg', """#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
if any(arg.endswith('bad.wav') for arg in args):
    sys.exit(7)
os.execv(os.environ['REAL_FFMPEG'], [os.environ['REAL_FFMPEG'], *args])
""")
        result = self.run_script('-n', '-j', '2')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue((self.music / 'bad.wav').exists())
        self.assertTrue(Path(str(good) + '.flac').exists())
        self.assertNotIn('Conversion process completed', result.stdout)

    @unittest.skipUnless(os.name == 'posix', 'POSIX process-group signals')
    def test_interruption_keeps_original_and_removes_unpublished_temp(self):
        source = self.wav()
        self.write_exe('ffmpeg', """#!/usr/bin/env python3
import sys, time
from pathlib import Path
Path(sys.argv[-1]).write_bytes(b'incomplete')
time.sleep(20)
""")
        process = subprocess.Popen([BASH, str(SCRIPT), '-n', str(self.music)],
                                   env=self.env, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and not list(self.music.glob('*.tmp.*')):
                time.sleep(0.02)
            self.assertTrue(list(self.music.glob('*.tmp.*')))
            self.assertFalse(Path(str(source) + '.flac').exists())
            os.killpg(process.pid, signal.SIGTERM)
            process.communicate(timeout=5)
            self.assertTrue(source.exists())
            self.assertFalse(Path(str(source) + '.flac').exists())
            self.assertFalse(list(self.music.glob('*.tmp.*')))
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.communicate()

    def test_aiff_stereo_audio_and_title_survive_conversion(self):
        source_wav = self.wav('source.wav')
        source_aiff = self.music / 'stereo.aiff'
        subprocess.run([FFMPEG, '-loglevel', 'error', '-i', str(source_wav),
                        '-ac', '2', '-metadata', 'title=Original title', str(source_aiff)], check=True)
        source_wav.unlink()
        result = self.run_script('-n')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = Path(str(source_aiff) + '.flac')
        self.assertTrue(output.exists())
        title = subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries',
                                         'format_tags=title', '-of', 'default=nw=1:nk=1',
                                         str(output)], text=True)
        self.assertEqual(title.strip(), 'Original title')
        self.assertTrue((self.music / '#recycle' / source_aiff.name).exists())

    def test_valid_audio_with_non_flac_signature_cannot_replace_original(self):
        source = self.wav()
        output = Path(str(source) + '.flac')
        shutil.copyfile(source, output)
        result = self.run_script('-n')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(source.exists())

    def test_invalid_job_counts_fail_before_conversion(self):
        source = self.wav()
        for value in ('0', '9', '-1', 'text', '9999999999999999999999999'):
            result = self.run_script('-j', value)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(source.exists())
            self.assertFalse(Path(str(source) + '.flac').exists())

    def test_conversion_succeeds_without_ffprobe(self):
        source = self.wav()
        no_ffprobe_bin = self.root / 'no_ffprobe_bin'
        no_ffprobe_bin.mkdir()
        for p in os.environ['PATH'].split(os.pathsep):
            if not p or not os.path.isdir(p):
                continue
            for item in os.listdir(p):
                if item != 'ffprobe' and not (no_ffprobe_bin / item).exists():
                    try:
                        (no_ffprobe_bin / item).symlink_to(Path(p) / item)
                    except OSError:
                        pass
        env = dict(self.env, PATH=str(self.bin) + os.pathsep + str(no_ffprobe_bin))
        result = subprocess.run([BASH, str(SCRIPT), '-n', str(self.music)],
                                env=env, text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(Path(str(source) + '.flac').exists())



if __name__ == '__main__':
    unittest.main()
