#!/usr/bin/env python3
"""Prepares one world and its catalog (docs/design/evaluation-e0.md, "Preparing the catalog").

    eval/prepare.py <task folder> [--app build/Gleaner.app]

Applies the epochs in history.json to world/, each anchored at the moment it is applied. After
each indexed epoch the bundled app runs with -GleanerHome <world> until the library's generation
counts that run, and is then stopped, so the app never reads a world halfway through an epoch. A
later epoch starts only once its whole span lies after the last index, so the logs read in order.
Nothing outside the world is read or written, apart from the app's own preferences.

Reads history.json from the world's gold folder (history.gold_folder) and writes prepared.json
there: when each epoch was applied, how long each index run took, the library's id and
generation, and its size on disk. Those are the preparation costs charged to the gleaner policy.
Both stay out of the policies' reach, since they say what changed after a delivery.
"""
import argparse
import contextlib
import json
import os
import signal
import sqlite3
import subprocess
import time

import history

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(REPO, 'build', 'Gleaner.app')


def library_folder(world):
    return os.path.join(world, 'Library', 'Application Support', 'Gleaner')


def meta(world):
    """The library's meta table, read only; empty while there is no library."""
    path = os.path.join(library_folder(world), 'registry.sqlite')
    if not os.path.exists(path):
        return {}
    try:
        with contextlib.closing(sqlite3.connect(f'file:{path}?mode=ro', uri=True)) as db:
            return dict(db.execute('SELECT key, value FROM meta'))
    except sqlite3.Error:
        return {}


def instances(world):
    """The app processes running with this world for their home."""
    listing = subprocess.run(['ps', '-axww', '-o', 'pid=,command='], capture_output=True, text=True, check=True).stdout
    found = []
    for row in listing.splitlines():
        pid, _, command = row.strip().partition(' ')
        if command.endswith(' -GleanerHome ' + world) or (' -GleanerHome ' + world + ' ') in command:
            found.append(int(pid))
    return found


def stop(world, timeout=15):
    """Stops the app instance for this world, as `pkill -f "GleanerHome <world>"` would."""
    for pid in instances(world):
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + timeout
    while instances(world):
        if time.time() > deadline:
            for pid in instances(world):
                os.kill(pid, signal.SIGKILL)
        time.sleep(0.1)


def index(world, app, generation, timeout=120):
    """Runs the app on the world until the library's generation reaches `generation`, then stops it."""
    if instances(world):
        raise SystemExit(f'Gleaner is already running for {world}')
    started = time.time()
    subprocess.run(['open', '-n', app, '--args', '-GleanerHome', world], check=True)
    while int(meta(world).get('generation', 0)) < generation:
        if time.time() - started > timeout:
            stop(world)
            raise SystemExit(f'{world}: no index run finished within {timeout} s')
        time.sleep(0.1)
    finished = time.time()
    stop(world)
    return dict(seconds=round(finished - started, 3), generation=int(meta(world)['generation']))


def size(folder):
    total = 0
    for root, _, files in os.walk(folder):
        total += sum(os.lstat(os.path.join(root, name)).st_size for name in files)
    return total


def prepare(folder, app=APP, say=print):
    """Applies the world's later epochs and indexes it; returns what prepared.json records."""
    folder = history.place(folder)
    world = os.path.join(folder, 'world')
    gold = history.gold_folder(folder)
    record = os.path.join(gold, 'prepared.json')
    if os.path.exists(record):
        raise SystemExit(f'{folder} is already prepared, or its preparation stopped partway: write the world again')
    with open(os.path.join(gold, 'history.json'), encoding='utf-8') as f:
        epochs = json.load(f)['epochs']
    # Marks the world at once, so a preparation that stops partway is never applied twice.
    with open(record, 'w', encoding='utf-8') as f:
        f.write('{"state": "preparing"}\n')
    applied, runs, last = [], [], None
    for number, epoch in enumerate(epochs, 1):
        if last is not None:
            wait = last + epoch['span'] + 1 - time.time()
            if wait > 0:
                time.sleep(wait)
        anchor = time.time()
        history.apply(world, epoch['ops'], anchor)
        applied.append(dict(epoch=number, at=history.iso(anchor), indexed=epoch['index']))
        if epoch['index']:
            runs.append(dict(index(world, app, len(runs) + 1), epoch=number))
            last = time.time()
            say(f'{os.path.basename(folder)}: epoch {number} indexed in {runs[-1]["seconds"]} s')
    library = meta(world)
    objects = os.path.join(library_folder(world), 'objects')
    prepared = dict(
        epochs=applied, index_runs=runs, library=library.get('library'), generation=int(library.get('generation', 0)),
        index_seconds=round(sum(run['seconds'] for run in runs), 3),
        library_bytes=size(library_folder(world)),
        saved_copies=sum(len(files) for _, _, files in os.walk(objects)))
    with open(record, 'w', encoding='utf-8') as f:
        json.dump(prepared, f, indent=2)
        f.write('\n')
    return prepared


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('folders', nargs='+', help='task folders written by worlds.py')
    parser.add_argument('--app', default=APP, help='the bundled app (default: build/Gleaner.app)')
    args = parser.parse_args()
    for folder in args.folders:
        prepare(folder, os.path.abspath(args.app))


if __name__ == '__main__':
    main()
