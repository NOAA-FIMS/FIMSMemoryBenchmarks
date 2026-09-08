import unittest

from check_leaks import allocation_origin, origin_report, parse_records


class LeakOriginsTest(unittest.TestCase):
    def test_macos_source_and_missing_stack(self):
        records = parse_records('''Leak: 0x100 size=1536 zone: default
Call stack:
0 libsystem_malloc.dylib 0x123 malloc + 12
1 FIMS.so 0x456 quadra::allocate() + 20 model.cpp:42
Leak: 0x200 size=64 zone: default
''', 'Darwin')
        self.assertEqual(records[0]['origin'], 'Quadra')
        self.assertIn('model.cpp:42', records[0]['caller'])
        self.assertEqual(records[1]['caller'], 'Stack unavailable')

    def test_memcheck_indirect_not_double_counted(self):
        text = '''==12== 120 (40 direct, 80 indirect) bytes in 1 blocks are definitely lost in loss record 1 of 4
==12==    at 0x123: malloc (malloc.c:10)
==12==    by 0x456: TMBad::allocate() (tape.cpp:20)
==12==
==12== 80 bytes in 2 blocks are indirectly lost in loss record 2 of 4
==12==    at 0x123: malloc (malloc.c:10)
==12==
==12== 500 bytes in 3 blocks are still reachable in loss record 3 of 4
==12==    at 0x123: malloc (malloc.c:10)
==12==
==12== 20 bytes in 1 blocks are possibly lost in loss record 4 of 4
==12==    at 0x123: malloc (malloc.c:10)
'''
        records = parse_records(text, 'Linux')
        self.assertEqual(sum(r['bytes'] for r in records), 140)
        self.assertEqual(records[0]['origin'], 'TMB/TMBad')
        self.assertEqual(len(records), 3)

    def test_nearest_caller_and_coverage(self):
        self.assertEqual(allocation_origin(['Rf_allocVector (libR.so)', 'quadra::evaluate()'])[0], 'R runtime')
        records = parse_records('Leak: 0x123 size=10 zone: default', 'Darwin')
        report = '\n'.join(origin_report({'ref': 'test', 'leak_records': records, 'metrics': {'leaked_bytes': 20}}))
        self.assertIn('10 of 20', report)
        self.assertIn('incomplete or inconsistent', report)
        self.assertIn('Stack unavailable', report)


if __name__ == '__main__':
    unittest.main()
