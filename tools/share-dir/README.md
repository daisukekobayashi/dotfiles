# share-dir

Start a temporary Dockerized FileBrowser Quantum instance for one local directory.

## Usage

```bash
share-dir .
share-dir ~/work --port 8088
share-dir . --host 127.0.0.1
share-dir . --readonly
share-dir . --user 1001:1001
```

Defaults:

- shared directory: current directory
- host bind: `0.0.0.0`
- port: auto-selected free local port
- container user: current host `uid:gid`
- login user: `admin`
- password: generated for each run
- backend: FileBrowser Quantum `stable-slim`

`share-dir` prints the URL, username, password, shared path, and stop instruction before starting Docker. Stop it with `Ctrl-C`.

## SSH Tunnel

For SSH-only access, bind the remote server to localhost and forward it from your local machine:

```bash
share-dir . --host 127.0.0.1 --port 18080
ssh -L 8080:127.0.0.1:18080 server
```

Then open `http://127.0.0.1:8080` locally.

## Security Notes

This tool is a convenience wrapper, not a security boundary. Docker avoids host-level installation and makes cleanup easier, but endpoint security can still inspect container layers, bind-mounted files, and running processes.

The default `0.0.0.0` bind is reachable from other hosts if network and firewall rules allow it. A random password is always generated, but use `--host 127.0.0.1` when direct network access is not needed.

Only the requested directory is mounted into the container. Use `--readonly` when upload or edit access is unnecessary.
