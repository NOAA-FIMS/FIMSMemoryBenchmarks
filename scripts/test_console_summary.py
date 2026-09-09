import json
from pathlib import Path
import tempfile
import unittest

from console_summary import build_rss, leaked_bytes, render


class ConsoleSummaryTest(unittest.TestCase):
    def test_rss_units(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'build.txt'
            path.write_text('2097152 maximum resident set size\n')
            self.assertEqual(build_rss(path, 'Darwin'), 2097152)
            path.write_text('Maximum resident set size (kbytes): 2048\n')
            self.assertEqual(build_rss(path, 'Linux'), 2097152)

    def test_leaks_exclude_reachable_and_failed_results(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'leaks.json'
            metrics = {'definitely lost': 10, 'indirectly lost': 20,
                       'possibly lost': 30, 'still reachable': 1000, 'suppressed': 100}
            path.write_text(json.dumps({'status': 'leaks detected', 'metrics': metrics}))
            self.assertEqual(leaked_bytes(path)[0], 60)
            path.write_text(json.dumps({'status': 'failed', 'metrics': metrics}))
            self.assertEqual(leaked_bytes(path), (None, 'failed'))
            path.write_text(json.dumps({'status': 'no leaks detected', 'metrics': {'leaked_bytes': 0}}))
            self.assertEqual(leaked_bytes(path)[0], 0)

    def test_comparison_and_missing_values(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)
            (p / 'rss').write_text('1048576 maximum resident set size\n')
            (p / 'time').write_text('2.5')
            (p / 'leaks').write_text(json.dumps({'status': 'leaks detected', 'metrics': {'leaked_bytes': 512}}))
            first = ['first', str(p/'rss'), str(p/'time'), str(p/'rss'), str(p/'leaks')]
            second = ['second', str(p/'rss'), str(p/'time'), str(p/'missing'), str(p/'missing')]
            output = render([first, second], 'Darwin')
            self.assertIn('512 B', output)
            self.assertIn('2.500 s', output)
            self.assertIn('Build peak process RSS: comparison unavailable', output)
            self.assertIn('Leaked/lost bytes: comparison unavailable', output)
            self.assertNotIn('Change:', render([first], 'Darwin'))


if __name__ == '__main__':
    unittest.main()
