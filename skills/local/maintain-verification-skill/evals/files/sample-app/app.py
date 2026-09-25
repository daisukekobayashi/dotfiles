import sys

if len(sys.argv) == 3 and sys.argv[1] == "render":
    print(sys.argv[2].upper())
elif sys.argv[1:] == ["premium"]:
    print("Premium entitlement is unavailable in this installation.", file=sys.stderr)
    sys.exit(78)
else:
    print("Usage: python3 app.py render TEXT | premium", file=sys.stderr)
    sys.exit(2)
