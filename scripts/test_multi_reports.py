from pathlib import Path
import subprocess
import tempfile
import unittest

from console_summary import render as console
from summarize_macos import Run, parse_profile, render as macos
from summarize_massif import Run as MassifRun, Profile, render as massif


class MultiRefTests(unittest.TestCase):
    def test_ref_resolution_order_dedup_and_collisions(self):
        """run_fims_benchmark()'s ref handling, via the function it delegates to.

        resolve_refs() is the R side of what used to live in run_massif.sh: any
        number of refs, first one is the baseline, duplicates dropped in order,
        and refs that collide once made filename-safe rejected outright.
        """
        def resolve(*refs):
            first, rest = refs[0], list(refs[1:])
            expression = (
                'source("R/run_benchmark.R");'
                'refs <- suppressWarnings(resolve_refs({first}, {rest}));'
                'cat(refs, sep = "\n")'
            ).format(first=self._r_vector([first]), rest=self._r_vector(rest))
            return subprocess.run(['Rscript', '-e', expression],
                                  capture_output=True, text=True)

        kept = resolve('main', 'quadra', 'third', 'main')
        self.assertEqual(kept.returncode, 0, kept.stderr)
        self.assertEqual(kept.stdout.split(), ['main', 'quadra', 'third'])

        collision = resolve('a/b', 'a_b')
        self.assertNotEqual(collision.returncode, 0)
        self.assertIn('collide', collision.stderr)

        alone = resolve('main')
        self.assertEqual(alone.returncode, 0, alone.stderr)
        self.assertEqual(alone.stdout.split(), ['main'])

        for bad in ('', 'bad ref'):
            rejected = resolve(bad)
            self.assertNotEqual(rejected.returncode, 0, f'{bad!r} was accepted')

    @staticmethod
    def _r_vector(values):
        if not values:
            return 'character()'
        quoted = ', '.join('"{}"'.format(value) for value in values)
        return 'c({})'.format(quoted)

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
