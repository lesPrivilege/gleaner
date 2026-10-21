#!/usr/bin/env python3
"""Count a labeled Spike A sheet against the delivery rule (docs/SPEC.md §13).

    scripts/score-candidates.py out/candidates.tsv

`gleaner-spike` writes a row per candidate, with whether the §9 rule admits it (`admitted`, yes
or no) and an empty `label`. A person labels the rows they check `delivery`, `not_delivery` or
`uncertain`, and leaves the rest empty. This compares the rows labeled delivery or not_delivery
with `admitted` and prints one JSON object:

- `input_sha256`, of the bytes it read;
- `counts`: the `rows`; `tp`, admitted deliveries; `fp`, admitted non-deliveries; `tn`, rejected
  non-deliveries; `fn`, rejected deliveries; and the `uncertain` and `unlabeled` rows, which
  count nowhere else;
- `label_coverage`, the share of rows labeled delivery or not_delivery;
- `admission_precision`, tp / (tp + fp), and `admission_recall`, tp / (tp + fn), each null when
  there is nothing to divide by;
- `rejected_deliveries` and `admitted_non_deliveries`: the ids of the fn and fp rows, to find in
  the sheet.

Both rates hold for the labeled rows alone, which need not represent the rest unless they were
drawn at random. A delivery the extractor never offered is not in the sheet, so admission_recall
is not the recall Gate 1 asks for (SPEC §12); the recall sample measures that.

The sheet is read once and never written. Its format is the one gleaner-spike writes: UTF-8, a
header row, LF line endings, cells split by tabs and no quoting, so a quote is an ordinary
character. Columns are found by name, and each id must be the 12 hex digits gleaner-spike writes.
A sheet that doesn't read whole gets no report: stderr says what is wrong, by line or column, and
the exit status is 2. Nothing from the sheet is printed but those ids.
"""
import argparse, hashlib, json, re, sys

LABELS = ('delivery', 'not_delivery', 'uncertain', '')
# Every label and admission pair, and the outcome it counts as.
OUTCOMES = {
    ('delivery', True): 'tp', ('not_delivery', True): 'fp',
    ('not_delivery', False): 'tn', ('delivery', False): 'fn',
    ('uncertain', True): 'uncertain', ('uncertain', False): 'uncertain',
    ('', True): 'unlabeled', ('', False): 'unlabeled',
}
NOTE = ('The rates count only rows labeled delivery or not_delivery, which need not represent the '
        'rest unless drawn at random. Deliveries the extractor never offered are not in the sheet, '
        "so admission_recall is not Gate 1's recall (SPEC section 12).")
SHOWN = 20  # problems listed before the rest are counted
ID = re.compile('[0-9a-f]{12}')  # the only text from the sheet a report prints


class Refused(Exception):
    """The sheet doesn't read whole; args[0] lists what is wrong."""


def rows(data):
    """The sheet's rows as (id, label, admitted), or Refused."""
    try:
        text = data.decode('utf-8-sig')
    except UnicodeDecodeError as error:
        line = data.count(b'\n', 0, error.start) + 1
        raise Refused([f'line {line}: not UTF-8'])
    if '\r' in text:
        # gleaner-spike reads its labels back from LF lines only, so a rerun would drop them all.
        line = text.count('\n', 0, text.index('\r')) + 1
        raise Refused([f'line {line}: a carriage return; save the sheet with LF line endings, as gleaner-spike writes it'])
    lines = text.split('\n')
    if lines[-1] == '':
        lines.pop()
    header = lines[0].split('\t') if lines else []
    missing = [name for name in ('id', 'label', 'admitted') if name not in header]
    if missing:
        raise Refused([f"no {', '.join(missing)} column{'s' if len(missing) > 1 else ''} in the header"])
    # A header cell may be text from a row, so a repeated name is told by its columns alone.
    repeated = [str(column) for column, name in enumerate(header, start=1) if header.count(name) > 1]
    if repeated:
        raise Refused(['the header gives columns ' + ', '.join(repeated) + ' the same name'])

    at = {name: header.index(name) for name in ('id', 'label', 'admitted')}
    found, problems, first = [], [], {}
    for number, line in enumerate(lines[1:], start=2):
        cells = line.split('\t')
        if len(cells) != len(header):
            problems.append(f"line {number}: {len(cells)} cell{'s' if len(cells) > 1 else ''}, where the header has {len(header)}")
            continue
        row_id, label, admitted = cells[at['id']], cells[at['label']], cells[at['admitted']]
        if not row_id:
            problems.append(f'line {number}: no id')
        elif not ID.fullmatch(row_id):
            problems.append(f'line {number}: an id other than the 12 hex digits gleaner-spike writes')
        elif row_id in first:
            problems.append(f'line {number}: repeats the id of line {first[row_id]}')
        else:
            first[row_id] = number
        if label not in LABELS:
            problems.append(f'line {number}: a label other than delivery, not_delivery, uncertain or empty')
        if admitted not in ('yes', 'no'):
            problems.append(f'line {number}: admitted is neither yes nor no')
        found.append((row_id, label, admitted == 'yes'))
    if problems:
        raise Refused(problems)
    return found


def ratio(part, whole):
    return part / whole if whole else None


def report(data):
    ids = {outcome: [] for outcome in ('tp', 'fp', 'tn', 'fn', 'uncertain', 'unlabeled')}
    for row_id, label, admitted in rows(data):
        ids[OUTCOMES[label, admitted]].append(row_id)
    n = {outcome: len(found) for outcome, found in ids.items()}
    total = sum(n.values())
    return {
        'schema_version': 1,
        'input_sha256': hashlib.sha256(data).hexdigest(),
        'counts': {'rows': total, **n},
        'label_coverage': ratio(n['tp'] + n['fp'] + n['tn'] + n['fn'], total),
        'admission_precision': ratio(n['tp'], n['tp'] + n['fp']),
        'admission_recall': ratio(n['tp'], n['tp'] + n['fn']),
        'rejected_deliveries': sorted(ids['fn']),
        'admitted_non_deliveries': sorted(ids['fp']),
        'note': NOTE,
    }


def main():
    parser = argparse.ArgumentParser(description='Count a labeled Spike A sheet against the delivery rule.')
    parser.add_argument('sheet', help="gleaner-spike's candidates.tsv, labeled")
    sheet = parser.parse_args().sheet
    try:
        with open(sheet, 'rb') as file:
            data = file.read()
        result = report(data)
    except OSError as error:
        problems = [f"can't read {sheet}: {error.strerror or error}"]
    except Refused as refusal:
        problems = refusal.args[0]
    else:
        json.dump(result, sys.stdout, indent=2)
        print()
        return 0
    for problem in problems[:SHOWN]:
        print(f'{parser.prog}: {problem}', file=sys.stderr)
    if len(problems) > SHOWN:
        print(f'{parser.prog}: and {len(problems) - SHOWN} more', file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main())
