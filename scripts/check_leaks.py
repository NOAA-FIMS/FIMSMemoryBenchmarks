#!/usr/bin/env python3
"""Run a separate joint-validation leak check and summarize native tool output."""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess


def parse_summary(text, host):
    if host == 'Darwin':
        matches = re.findall(r'Process \d+: ([\d,]+) leaks? for ([\d,]+) total leaked bytes', text)
        if not matches:
            return None
        count, size = matches[-1]
        return {'leak_count': int(count.replace(',', '')), 'leaked_bytes': int(size.replace(',', ''))}
    values = {}
    for kind in ['definitely lost', 'indirectly lost', 'possibly lost', 'still reachable', 'suppressed']:
        matches = re.findall(re.escape(kind) + r':\s*([\d,]+) bytes in ([\d,]+) blocks', text)
        if matches:
            values[kind] = int(matches[-1][0].replace(',', ''))
    if 'All heap blocks were freed -- no leaks are possible' in text:
        return {kind: 0 for kind in ['definitely lost', 'indirectly lost', 'possibly lost', 'still reachable', 'suppressed']}
    return values if len(values) == 5 else None


def allocation_origin(frames):
    """Use the nearest recognizable allocation caller, not a distant ancestor."""
    for frame in frames:
        lower = frame.lower()
        if 'quadra' in lower:
            return 'Quadra', frame
        if 'tmbad' in lower or re.search(r'\btmb(?:::|\b)', lower):
            return 'TMB/TMBad', frame
        if 'rcpp' in lower:
            return 'Rcpp', frame
        if 'fims' in lower:
            return 'FIMS C++ (backend not explicit)', frame
        if re.search(r'libR\.(?:so|dylib)|\b(?:Rf_|R_)[A-Za-z]', frame):
            return 'R runtime', frame
    return 'System/other/unresolved', frames[0] if frames else 'Stack unavailable'


def parse_records(text, host):
    records = []
    current = None
    number = lambda value: int(value.replace(',', ''))
    for line_number, raw in enumerate(text.splitlines(), 1):
        line = re.sub(r'^==\d+==\s?', '', raw)
        if host == 'Darwin':
            match = re.match(r'Leak:.*?size=([\d,]+)', line)
            if match:
                current = dict(kind='leaked', bytes=number(match[1]), blocks=1, frames=[], log_line=line_number)
                records.append(current)
            elif current and re.match(r'^\d+\s+\S+\s+0x[0-9a-fA-F]+', line):
                current['frames'].append(line.strip())
        else:
            match = re.match(r'([\d,]+)(?: \(([\d,]+) direct, ([\d,]+) indirect\))? bytes in ([\d,]+) blocks are (definitely lost|indirectly lost|possibly lost|still reachable|suppressed) in loss record', line)
            if match:
                # Direct+indirect totals repeat the indirect records: count direct only here.
                current = dict(kind=match[5], bytes=number(match[2] or match[1]), blocks=number(match[4]), frames=[], log_line=line_number)
                records.append(current)
            elif current and re.match(r'\s*(?:at|by) 0x[0-9a-fA-F]+:', line):
                current['frames'].append(line.strip())
            elif not line.strip():
                current = None
    for record in records:
        record['origin'], record['caller'] = allocation_origin(record['frames'])
    return [r for r in records if r['kind'] not in ('still reachable', 'suppressed')]


def origin_report(data):
    records = data.get('leak_records', [])
    lines = ['', '## Allocation origins: ' + data['ref'].replace('|', '\\|'), '']
    if not records:
        return lines + ['No parsed leak allocation records are available. See the check status and raw log; missing stacks do not imply zero leaks.', '']
    groups = {}
    for record in records:
        key = (record['origin'], record['kind'])
        group = groups.setdefault(key, [0, 0])
        group[0] += record['bytes']
        group[1] += record['blocks']
    lines += ['| Origin | Leak kind | Parsed bytes | Blocks |', '|---|---|---:|---:|']
    for (origin, kind), (size, blocks) in sorted(groups.items(), key=lambda item: -item[1][0]):
        lines.append(f'| {origin} | {kind} | {size:,} | {blocks:,} |')
    metrics = data.get('metrics') or {}
    expected = metrics.get('leaked_bytes', sum(metrics.get(k, 0) for k in ['definitely lost', 'indirectly lost', 'possibly lost']))
    parsed = sum(r['bytes'] for r in records)
    lines += ['', f'Parsed allocation records cover {parsed:,} of {expected:,} detector-reported leaked/lost bytes.']
    if parsed != expected:
        lines += ['Coverage is incomplete or inconsistent; use the raw detector totals as authoritative.']
    lines += ['', '### Largest leak allocation records', '', '| Origin | Kind | Bytes | Allocation caller (source location when available) | Raw log line |', '|---|---|---:|---|---:|']
    for record in sorted(records, key=lambda r: -r['bytes'])[:10]:
        caller = record['caller'].replace('|', '\\|').replace('`', "'")
        lines.append(f"| {record['origin']} | {record['kind']} | {record['bytes']:,} | `{caller}` | {record['log_line']} |")
    return lines + ['']


def run(ref, output):
    host = platform.system()
    tool = 'leaks' if host == 'Darwin' else 'valgrind'
    log = output.with_suffix('.log')
    marker = output.with_suffix('.completed')
    marker.unlink(missing_ok=True)
    result = {'ref': ref, 'tool': tool, 'status': 'disabled', 'metrics': None, 'log': log.name}
    if os.getenv('LEAK_CHECK', '1') != '1':
        pass
    elif not shutil.which(tool):
        result['status'] = 'unavailable'
    else:
        result['status'] = 'failed'
        try:
            r_home = subprocess.check_output(['Rscript', '-e', 'cat(R.home())'], text=True).strip()
            env = dict(os.environ, R_HOME=r_home, FIMS_LEAK_COMPLETED=str(marker.resolve()))
            # Launch R itself so the detector inspects R, not a shell launcher.
            # The joint fit is the workload: a leak that only shows up under
            # optimization is the one worth finding. FIMS_SIZE picks the fixture,
            # so a leak check can be run against the small model while iterating.
            workload = (
                "source('R/setup_FIMS.R'); "
                "inputs <- setup_fims_inputs(size = Sys.getenv('FIMS_SIZE', 'normal')); "
                "invisible(run_fims_validation(inputs)); "
                "gc(); writeLines('completed', Sys.getenv('FIMS_LEAK_COMPLETED')); "
                "quit(save='no', status=0)"
            )
            command = [str(Path(r_home) / 'bin/exec/R'), '--vanilla', '--slave', '-e', workload]
            if host == 'Darwin':
                env['MallocStackLogging'] = '1'
                command = [tool, '--list', '--fullStacks', '--atExit', '--', *command]
            else:
                command = [tool, '--tool=memcheck', '--leak-check=full', '--show-leak-kinds=all',
                           '--num-callers=30', '--error-exitcode=99', *command]
            with log.open('w') as stream:
                completed = subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT)
            result['exit_code'] = completed.returncode
            metrics = parse_summary(log.read_text(errors='replace'), host)
            if marker.exists() and metrics is not None and completed.returncode in ([0, 1] if host == 'Darwin' else [0, 99]):
                result['metrics'] = metrics
                result['leak_records'] = parse_records(log.read_text(errors='replace'), host)
                leaked = metrics.get('leaked_bytes', 0) + sum(metrics.get(k, 0) for k in ['definitely lost', 'indirectly lost', 'possibly lost'])
                result['status'] = 'leaks detected' if leaked else 'no leaks detected'
                if host != 'Darwin' and completed.returncode == 99 and not leaked:
                    result['status'] = 'memory errors detected; no leaks detected'
        except (OSError, subprocess.SubprocessError) as error:
            log.write_text(str(error) + '\n')
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(f"Leak check {ref}: {result['status']}")


def report(paths, output):
    lines = ['# FIMS Leak Detection Report', '',
             'Each branch runs the joint-validation workload in a separate process under a leak detector, followed by R garbage collection and exit. Installation and this instrumented run are excluded from total validation runtime.', '',
             'Results cover the entire R process, including FIMS, backend libraries, and dependencies. Inspect allocation stacks before attributing a leak to a backend. No leaks detected is limited to this workload and detector; reachable retained memory and growth across repeated model lifecycles require separate investigation.', '',
             '| Git ref | Detector | Status | Reported bytes by category | Raw log |', '|---|---|---|---|---|']
    for path in paths:
        data = json.loads(path.read_text())
        metrics = data['metrics']
        detail = '; '.join(f'{k}: {v:,}' for k, v in metrics.items()) if metrics is not None else 'Not measured'
        log = data['log']
        link = f'[{log}]({log})' if (path.parent / log).exists() else '—'
        ref = data['ref'].replace('|', '\\|')
        lines.append(f"| {ref} | {data['tool']} | {data['status']} | {detail} | {link} |")
    lines += ['', 'macOS reports unreachable leaked blocks and bytes. Memcheck separates definitely, indirectly, and possibly lost bytes from still-reachable and suppressed bytes; these categories are not directly comparable across detectors. Failed, disabled, or unavailable checks are not clean results.', '']
    lines += ['Origins identify the nearest recognizable allocation caller, not necessarily the code responsible for losing ownership. Unresolved stacks remain explicit. Full parsed stacks are retained in JSON and raw logs; source file/line availability depends on debug symbols.', '']
    for path in paths:
        lines += origin_report(json.loads(path.read_text()))
    output.write_text('\n'.join(lines))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ref')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--report', nargs='+', type=Path)
    args = parser.parse_args()
    if args.report:
        report(args.report, args.output)
    elif args.ref:
        run(args.ref, args.output)
    else:
        parser.error('--ref or --report is required')
