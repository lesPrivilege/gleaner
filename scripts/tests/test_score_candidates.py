"""scripts/score-candidates.py, run as a person runs it, on synthetic sheets.

    python3 -m unittest discover -s scripts/tests -v

labeled.tsv has gleaner-spike's columns and one row of each outcome, an uncertain row and an
unlabeled one. Its rows and labels are made up: they are no Gate 1 labels.
"""
import hashlib, json, pathlib, subprocess, sys, tempfile, unittest

HERE = pathlib.Path(__file__).resolve().parent
SCRIPT = HERE.parent / 'score-candidates.py'
LABELED = HERE / 'labeled.tsv'


class ScoreCandidatesTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.path = pathlib.Path(folder.name) / 'candidates.tsv'
        self.header, *self.rows = LABELED.read_text(encoding='utf-8').rstrip('\n').split('\n')
        self.names = self.header.split('\t')

    def run_on(self, data, *arguments):
        self.path.write_bytes(data)
        done = subprocess.run([sys.executable, '-I', str(SCRIPT), *(arguments or [str(self.path)])], capture_output=True)
        self.assertEqual(self.path.read_bytes(), data, 'the sheet is left as it was')
        return done.returncode, done.stdout.decode(), done.stderr.decode()

    def report(self, data):
        status, out, err = self.run_on(data)
        self.assertEqual((status, err), (0, ''))
        return json.loads(out)

    def refusal(self, data, *arguments):
        status, out, err = self.run_on(data, *arguments)
        self.assertEqual((status, out), (2, ''))
        self.assertTrue(err)
        return err

    def sheet(self, rows, header=None):
        return ('\n'.join([header or self.header, *rows]) + '\n').encode()

    def cell(self, row, name):
        return row.split('\t')[self.names.index(name)]

    def edited(self, row, **cells):
        values = row.split('\t')
        for name, value in cells.items():
            values[self.names.index(name)] = value
        return '\t'.join(values)

    def without(self, name, rows=None):
        """A sheet of `rows`, labeled.tsv's by default, with one column removed."""
        drop = self.names.index(name)
        def cut(line):
            return '\t'.join(cell for i, cell in enumerate(line.split('\t')) if i != drop)
        return self.sheet([cut(row) for row in (self.rows if rows is None else rows)], header=cut(self.header))

    def test_one_row_of_each_outcome(self):
        data = LABELED.read_bytes()
        report = self.report(data)
        self.assertEqual(report, {
            'schema_version': 1,
            'input_sha256': hashlib.sha256(data).hexdigest(),
            'counts': {'rows': 6, 'tp': 1, 'fp': 1, 'tn': 1, 'fn': 1, 'uncertain': 1, 'unlabeled': 1},
            'label_coverage': 4 / 6,
            'admission_precision': 0.5,
            'admission_recall': 0.5,
            'rejected_deliveries': ['000000000004'],
            'admitted_non_deliveries': ['000000000002'],
            'note': report['note'],
        })
        self.assertIn('need not represent the rest', report['note'])

    def test_nothing_admitted_has_no_precision(self):
        report = self.report(self.sheet([self.edited(row, admitted='no') for row in self.rows]))
        self.assertEqual(report['counts'], {'rows': 6, 'tp': 0, 'fp': 0, 'tn': 2, 'fn': 2, 'uncertain': 1, 'unlabeled': 1})
        self.assertIsNone(report['admission_precision'])
        self.assertEqual(report['admission_recall'], 0.0)
        self.assertEqual(report['rejected_deliveries'], ['000000000001', '000000000004'])

    def test_no_delivery_has_no_recall(self):
        rows = [self.edited(row, label='not_delivery') if self.cell(row, 'label') == 'delivery' else row for row in self.rows]
        report = self.report(self.sheet(rows))
        self.assertEqual(report['counts'], {'rows': 6, 'tp': 0, 'fp': 2, 'tn': 2, 'fn': 0, 'uncertain': 1, 'unlabeled': 1})
        self.assertEqual(report['admission_precision'], 0.0)
        self.assertIsNone(report['admission_recall'])

    def test_an_unlabeled_sheet(self):
        report = self.report(self.sheet([self.edited(row, label='') for row in self.rows]))
        self.assertEqual(report['counts'], {'rows': 6, 'tp': 0, 'fp': 0, 'tn': 0, 'fn': 0, 'uncertain': 0, 'unlabeled': 6})
        self.assertEqual(report['label_coverage'], 0.0)
        self.assertIsNone(report['admission_precision'])
        self.assertIsNone(report['admission_recall'])
        self.assertEqual((report['rejected_deliveries'], report['admitted_non_deliveries']), ([], []))

    def test_a_header_alone(self):
        report = self.report(self.sheet([]))
        self.assertEqual(report['counts'], {'rows': 0, 'tp': 0, 'fp': 0, 'tn': 0, 'fn': 0, 'uncertain': 0, 'unlabeled': 0})
        self.assertEqual([report[k] for k in ('label_coverage', 'admission_precision', 'admission_recall')], [None] * 3)

    def test_only_the_bytes_change_the_digest(self):
        data = LABELED.read_bytes()
        base = self.report(data)
        variants = {
            'rows in another order': self.sheet(self.rows[::-1]),
            'another note': self.sheet([self.edited(self.rows[0], note='synthetic: another note'), *self.rows[1:]]),
            'a byte order mark': b'\xef\xbb\xbf' + data,
            'no newline after the last row': data.rstrip(b'\n'),
        }
        for case, variant in variants.items():
            with self.subTest(case):
                report = self.report(variant)
                self.assertEqual(report['input_sha256'], hashlib.sha256(variant).hexdigest())
                self.assertNotEqual(report['input_sha256'], base['input_sha256'])
                self.assertEqual({**report, 'input_sha256': None}, {**base, 'input_sha256': None})

    def test_refuses_a_sheet_that_does_not_read_whole(self):
        first, second = self.rows[0], self.rows[1]
        data = LABELED.read_bytes()
        cases = {  # each with the problem it is refused for
            'an unlabeled sheet from before the admitted column': (self.without(
                'admitted', [self.edited(row, label='') for row in self.rows]), 'no admitted column in the header'),
            'no id column': (self.without('id'), 'no id column'),
            'no label column': (self.without('label'), 'no label column'),
            'a column twice': (self.sheet([row + '\tx' for row in self.rows], header=self.header + '\tnote'),
                               "the header repeats 'note'"),
            'a row short of a cell': (self.sheet([first.rsplit('\t', 1)[0], *self.rows[1:]]), 'line 2: 20 cells'),
            'a row with a cell more': (self.sheet([first + '\textra', *self.rows[1:]]), 'line 2: 22 cells'),
            'a blank line': (self.sheet([first, '', *self.rows[1:]]), 'line 3: 1 cell,'),
            'an empty id': (self.sheet([self.edited(first, id=''), *self.rows[1:]]), 'line 2: no id'),
            'an id twice': (self.sheet([first, self.edited(second, id=self.cell(first, 'id')), *self.rows[2:]]),
                            'line 3: repeats the id of line 2'),
            'a label in capitals': (self.sheet([self.edited(first, label='Delivery'), *self.rows[1:]]), 'line 2: a label'),
            'a label with a space after it': (self.sheet([self.edited(first, label='delivery '), *self.rows[1:]]),
                                              'line 2: a label'),
            'yes as a label': (self.sheet([self.edited(first, label='yes'), *self.rows[1:]]), 'line 2: a label'),
            'admitted in capitals': (self.sheet([self.edited(first, admitted='Yes'), *self.rows[1:]]), 'line 2: admitted'),
            'admitted empty': (self.sheet([self.edited(first, admitted=''), *self.rows[1:]]), 'line 2: admitted'),
            'CR LF line endings': (data.replace(b'\n', b'\r\n'), 'line 1: a carriage return'),
            'not UTF-8': (data.replace(b'synthetic: the chart', b'synthetic: the \xff chart'), 'line 5: not UTF-8'),
            'an empty file': (b'', 'no id, label, admitted columns in the header'),
        }
        for case, (variant, problem) in cases.items():
            with self.subTest(case):
                self.assertIn(problem, self.refusal(variant))

    def test_refuses_without_a_sheet(self):
        self.refusal(b'', str(self.path.with_name('absent.tsv')))
        self.refusal(b'', str(self.path.parent))
        status, out, _ = self.run_on(b'', '--')  # no sheet named at all
        self.assertEqual((status, out), (2, ''))

    def test_says_which_lines_are_wrong(self):
        rows = list(self.rows)
        rows[1] = self.edited(rows[1], label='yes')
        rows[4] = self.edited(rows[4], admitted='true')
        err = self.refusal(self.sheet(rows))
        self.assertEqual([line.split(': ')[1] for line in err.splitlines()], ['line 3', 'line 6'])

    def test_lists_twenty_problems_and_counts_the_rest(self):
        rows = [self.edited(self.rows[0], id=f'r{n}', label='?') for n in range(25)]
        lines = self.refusal(self.sheet(rows)).splitlines()
        self.assertEqual(len(lines), 21)
        self.assertTrue(lines[-1].endswith('and 5 more'))

    def test_prints_nothing_from_the_other_cells(self):
        secret = 'PRIVATE-7f3a'
        others = [name for name in self.names if name not in ('id', 'label', 'admitted')]
        rows = [self.edited(row, **{name: f'{secret} {name}' for name in others}) for row in self.rows]
        status, out, err = self.run_on(self.sheet(rows))
        self.assertEqual(status, 0)
        self.assertNotIn(secret, out + err)
        refused = {
            'a label that is private text': self.sheet([self.edited(rows[0], label=secret), *rows[1:]]),
            'a sheet whose header was deleted': self.sheet(rows[1:], header=rows[0]),
            'a row with a cell more': self.sheet([rows[0] + f'\t{secret}', *rows[1:]]),
        }
        for case, data in refused.items():
            with self.subTest(case):
                self.assertNotIn(secret, self.refusal(data))


if __name__ == '__main__':
    unittest.main()
