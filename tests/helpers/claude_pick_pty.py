"""Run picker contract tests with a real terminal and a bounded lifetime."""

import errno
import os
import pty
import select
import signal
import sys
import time

pid, terminal = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])

output = bytearray()
sent_name = False
deadline = time.monotonic() + 10
try:
    while time.monotonic() < deadline:
        readable, _, _ = select.select([terminal], [], [], 0.1)
        if readable:
            try:
                chunk = os.read(terminal, 65536)
            except OSError as exc:
                if exc.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            output.extend(chunk)
            if not sent_name and b"New profile name:" in output:
                os.write(terminal, (os.environ.get("PICK_TEST_NAME", "") + "\n").encode())
                sent_name = True
    else:
        os.kill(pid, signal.SIGKILL)
        raise TimeoutError("claude-pick did not finish within 10 seconds")
    _, status = os.waitpid(pid, 0)
    sys.stdout.buffer.write(output)
    sys.exit(os.waitstatus_to_exitcode(status))
finally:
    os.close(terminal)
