# SPDX-License-Identifier: GPL-3.0-or-later
"""Data-only host ownership receipts. Never starts any process or executable."""
import argparse
import importlib.util
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('fixture_host_owned', ROOT / 'scripts/run/android/android-owned-process.py')
owned = importlib.util.module_from_spec(spec)
spec.loader.exec_module(owned)


def capture(directory, program, arguments, completed=True, supervisor_pid=4242, frontend_pid=4243, artifact_root=None, adb_endpoint=None, cwd=None):
    directory, program = Path(directory).resolve(), Path(program).resolve()
    request = {'schema_version': 1, 'run_id': uuid.uuid4().hex, 'owner_pid': 1,
               'owner_creation_filetime': '1', 'program': str(program), 'program_sha256': owned.digest(program),
               'arguments': arguments, 'cwd': str(Path(cwd).resolve() if cwd is not None else directory), 'stdout': 'emulator.stdout', 'stderr': 'emulator.stderr'}
    request['adb_endpoint'] = adb_endpoint or {'schema_version': 1, 'host': 'localhost', 'port': 5037, 'socket': 'tcp:localhost:5037'}
    if artifact_root is not None:
        request['artifact_lease']={'root':str(Path(artifact_root).resolve()),'handle':'123'}
    owned.write(directory / owned.REQUEST, request)
    owner = {'schema_version': 1, 'backend': owned.BACKEND, 'run_id': request['run_id'],
             'request_sha256': owned.digest(directory / owned.REQUEST), 'supervisor_pid': supervisor_pid,
             'supervisor_creation_filetime': '123', 'frontend_pid': frontend_pid,
             'frontend_creation_filetime': '456', 'contained_before_start': True, 'host_slot': owned.HOST_SLOT, 'host_slot_acquired_before_start': True, 'adb_endpoint_applied_before_start': True}
    if artifact_root is not None:
        owner.update(artifact_lease_held=True,artifact_lease_root=str(Path(artifact_root).resolve()))
    owned.write(directory / owned.OWNER, owner)
    for key in ('stdout', 'stderr'):
        if not (directory / request[key]).exists():
            (directory / request[key]).write_text('synthetic host output only')
    (directory / 'emulator.pid').write_text(str(frontend_pid))
    (directory / 'emulator-supervisor.pid').write_text(str(supervisor_pid))
    return finish(directory) if completed else {
        'host_process_request_sha256': owner['request_sha256'], 'host_process_owner_sha256': owned.digest(directory / owned.OWNER)}


def finish(directory):
    directory = Path(directory)
    request, request_sha = owned.request(directory)
    owner, owner_sha = owned.read(directory / owned.OWNER)
    proof = {'schema_version': 1, 'backend': owned.BACKEND, 'run_id': request['run_id'],
             'request_sha256': request_sha, 'owner_sha256': owner_sha,
             'supervisor_pid': owner['supervisor_pid'], 'frontend_pid': owner['frontend_pid'],
             'active_processes': 0, 'total_processes': 3, 'frontend_exit_code': 0,
             'reason': 'requested', 'forced': True, 'frontend_exited_before_stop': True,
             'host_tree_exit_confirmed': True, 'host_slot_held_until_tree_exit': True, 'frontend_signaled': True, 'logs_closed_before_hash': True,
             'stdout_sha256': owned.digest(directory / request['stdout']), 'stderr_sha256': owned.digest(directory / request['stderr'])}
    if 'artifact_lease' in request:
        proof['artifact_lease_held_until_exit']=True
    owned.write(directory / owned.EXIT, proof)
    return owned.validate(directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('capture', 'finish'))
    parser.add_argument('--directory', required=True, type=Path)
    parser.add_argument('--spec', type=Path)
    args = parser.parse_args()
    if args.action == 'capture':
        value, _ = owned.read(args.spec)
        result = capture(args.directory, value['program'], value['arguments'], completed=False,
                         supervisor_pid=value['supervisor_pid'], frontend_pid=value['frontend_pid'],artifact_root=value.get('artifact_root'), adb_endpoint=value.get('adb_endpoint'))
    else:
        result = finish(args.directory)
    import json
    print(json.dumps(result))


if __name__ == '__main__':
    main()
