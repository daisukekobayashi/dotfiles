"""Print the open tasks in tasks.csv as a CSV report."""
import csv
import sys

FIELDS = ["id", "title", "owner", "due"]


def main(argv):
    with open("tasks.csv", newline="") as source:
        rows = [row for row in csv.DictReader(source) if row["status"] == "open"]
    writer = csv.DictWriter(sys.stdout, fieldnames=FIELDS, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(rows)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
