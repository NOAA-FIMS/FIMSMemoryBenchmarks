#!/usr/bin/env python3
"""Print peak RSS and total validation runtime from saved benchmark results."""

import argparse
import math
import json
import re
from pathlib import Path

from summarize_macos import human_bytes, parse_profile


def runtime(path):
    if not path.is_file():
        return None
    value = float(path.read_text().strip())
    if not math.isfinite(value) or value < 0:
        raise ValueError(f"Invalid runtime in {path}")
    return value


def build_rss(path, host):
    path = Path(path)
    if not path.is_file():
        return None
    if host == 'Darwin':
        return parse_profile(path).maximum_rss
    match = re.search(r'Maximum resident set size \(kbytes\):\s*(\d+)', path.read_text())
    return int(match[1]) * 1024 if match else None


def leaked_bytes(path):
    path = Path(path)
    if not path.is_file():
        return None, 'Not recorded'
    data = json.loads(path.read_text())
    status = data.get('status', 'unknown')
    metrics = data.get('metrics')
    if not metrics or status not in ('leaks detected', 'no leaks detected', 'memory errors detected; no leaks detected'):
        return None, status
    if 'leaked_bytes' in metrics:
        return metrics['leaked_bytes'], status
    kinds = ['definitely lost', 'indirectly lost', 'possibly lost']
    if all(k in metrics for k in kinds):
        return sum(metrics[k] for k in kinds), status
    return None, 'Incomplete leak summary'


def render(runs, host):
    values = []
    for ref, profile, timing, build, leaks in runs:
        rss = parse_profile(Path(profile)).maximum_rss if host == 'Darwin' and Path(profile).is_file() else None
        leaked, status = leaked_bytes(leaks)
        values.append((ref, rss, runtime(Path(timing)), build_rss(build, host), leaked, status))
    rows = [['Branch', 'Peak RSS (inner run)', 'Total validation runtime', 'Build peak process RSS', 'Leaked/lost bytes', 'Leak status']]
    for ref, rss, elapsed, build, leaked, status in values:
        rows.append([ref, human_bytes(rss) if rss is not None else 'Not recorded',
                     f'{elapsed:.3f} s' if elapsed is not None else 'Not recorded',
                     human_bytes(build) if build is not None else 'Not recorded',
                     f'{leaked:,} B' if leaked is not None else 'Not recorded', status])
    widths = [max(len(row[i]) for row in rows) for i in range(len(rows[0]))]
    lines = ['', 'Branch comparison', '']
    for index, row in enumerate(rows):
        lines.append('  '.join(cell.ljust(width) for cell, width in zip(row, widths)).rstrip())
        if index == 0:
            lines.append('  '.join('-' * width for width in widths))
    if len(values) == 2:
        first, second = values
        lines += ['', f'Change: {second[0]} relative to {first[0]}']
        for column, label, unit in [(1, 'Peak RSS', 'MiB'), (2, 'Total validation runtime', 's'),
                                    (3, 'Build peak process RSS', 'MiB'), (4, 'Leaked/lost bytes', 'B')]:
            baseline, comparison = first[column], second[column]
            if baseline is None or comparison is None:
                lines.append(f'  {label}: comparison unavailable')
                continue
            difference = comparison - baseline
            display = difference / (1024 ** 2) if column in (1, 3) else difference
            percent = f'{difference / baseline * 100:+.2f}%' if baseline else 'percentage undefined (zero baseline)'
            lines.append(f'  {label}: {display:+.3f} {unit} ({percent})')
    lines += ['', 'RSS covers the separate inner/setup-evaluation workload; backend objective treatments may differ.',
              'Runtime covers the complete joint-validation R process, including setup and optimization.',
              'Installation and separate profiler/leak-check runs are excluded from that runtime.',
              'Build RSS is the OS-reported maximum per-process RSS for installation, not summed concurrent compiler RSS.',
              'Leaked/lost bytes come from the separate leak check; Memcheck includes definite, indirect, and possible losses.',
              'Reachable and suppressed allocations are excluded; unknown or failed checks are not zero leaks.']
    if host != 'Darwin':
        lines.append('Peak RSS is not collected by the current Linux runner; Massif heap usage is a different metric.')
    return '\n'.join(lines)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', required=True)
    parser.add_argument('--run', nargs=5, action='append', required=True,
                        metavar=('REF', 'RSS_PROFILE', 'RUNTIME', 'BUILD_PROFILE', 'LEAK_JSON'))
    args = parser.parse_args()
    print(render(args.run, args.platform))
