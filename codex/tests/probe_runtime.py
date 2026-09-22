#!/usr/bin/env python3
"""Read packages through Codex app-server without installing or enabling them."""
import argparse
import json
from pathlib import Path
import queue
import subprocess
import tempfile
import threading


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('marketplace_root', type=Path)
    args = parser.parse_args()
    marketplace = args.marketplace_root.resolve() / '.agents/plugins/marketplace.json'
    if not marketplace.is_file():
        parser.error(f'missing marketplace: {marketplace}')
    with tempfile.TemporaryFile(mode='w+') as errors:
        process = subprocess.Popen(['codex', 'app-server', '--stdio'], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=errors, text=True, bufsize=1)
        messages = queue.Queue()

        def read():
            for line in process.stdout:
                messages.put(json.loads(line))
            messages.put(None)

        reader = threading.Thread(target=read, daemon=True)
        reader.start()

        def request(number, method, params):
            process.stdin.write(json.dumps({'id': number, 'method': method, 'params': params}) + '\n')
            process.stdin.flush()
            while True:
                message = messages.get(timeout=30)
                if message is None:
                    raise RuntimeError('Codex app-server exited; check access to its state directory')
                if message.get('id') == number:
                    if 'error' in message:
                        raise RuntimeError(message['error'])
                    return message['result']

        try:
            request(1, 'initialize', {'clientInfo': {'name': 'gox-package-probe', 'version': '0.1.0'}})
            process.stdin.write('{"method":"initialized"}\n')
            process.stdin.flush()
            for number, name, skill_count, events in [
                (2, 'gox-code-rules', 4, {'sessionStart', 'subagentStart'}),
                (3, 'gox-guard', 0, {'sessionStart', 'preToolUse'}),
            ]:
                plugin = request(number, 'plugin/read', {
                    'marketplacePath': str(marketplace), 'pluginName': name,
                })['plugin']
                if len(plugin['skills']) != skill_count:
                    raise RuntimeError(f'{name}: unexpected skills: {plugin["skills"]}')
                if {hook['eventName'] for hook in plugin['hooks']} != events:
                    raise RuntimeError(f'{name}: unexpected hooks: {plugin["hooks"]}')
                print(f'OK {name}: {skill_count} skills, {len(events)} hook events')
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            process.stdin.close()
            reader.join(timeout=5)
            process.stdout.close()


if __name__ == '__main__':
    main()
