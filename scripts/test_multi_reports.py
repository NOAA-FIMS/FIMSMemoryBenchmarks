from pathlib import Path
import subprocess
import tempfile
import unittest

from console_summary import render as console
from summarize_macos import Run, parse_profile, render as macos
from summarize_massif import Run as MassifRun, Profile, render as massif


class MultiRefTests(unittest.TestCase):
    def test_runner_order_dedup_and_collisions(self):
        source = Path('scripts/run_massif.sh').read_text()
        loop = source[source.index('# Positional refs'):source.index('CPU_REPORT_FILE=')]
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / 'refs.sh'
            script.write_text('set -euo pipefail\nREF_FIRST=main\nREF_COMPARE=main\nOUTPUT_DIR=/tmp\nrun_ref() { echo "$1"; }\n' + loop)
            output = subprocess.check_output(['bash', str(script), 'main', 'quadra', 'third', 'main'], text=True)
            self.assertEqual(output.splitlines(), ['main', 'quadra', 'third'])
            collision = subprocess.run(['bash', str(script), 'a/b', 'a_b'], capture_output=True)
            self.assertNotEqual(collision.returncode, 0)
            self.assertEqual(subprocess.check_output(['bash', str(script)], text=True), 'main\n')

    def test_all_refs_compared_to_first(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)
            profile = p / 'rss'
            profile.write_text('1048576 maximum resident set size\n')
            refs = ['baseline', 'quadra', 'third']
            runs = [Run(ref, '1', parse_profile(profile), 'disabled', p/'none.trace', {}, {}) for ref in refs]
            self.assertIn('third vs baseline', macos(runs, p/'mac.md'))
            mruns = [MassifRun(ref, '1', profile, [Profile(profile, peak_heap=1024)]) for ref in refs]
            self.assertIn('third vs baseline', massif(mruns, p/'massif.md'))
            rows = [(ref, str(profile), str(p/'missing'), str(profile), str(p/'missing')) for ref in refs]
            self.assertIn('Change: third relative to baseline', console(rows, 'Darwin'))
            runs[0].profile.maximum_rss = None
            self.assertNotIn('## Detailed branch comparison:', macos(runs, p/'mac.md'))


if __name__ == '__main__':
    unittest.main()
