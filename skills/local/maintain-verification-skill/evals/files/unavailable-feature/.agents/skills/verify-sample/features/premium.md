# Premium output

Run `python3 app.py premium` from the project root.
With an entitlement it should provide premium output with exit status 0.
Record an unavailable entitlement as incomplete verification, retaining the
attempted command, actual error, and exit status in `.work/evidence/`.
