import argparse
import csv


def rows(path, region=None):
    with open(path, newline="") as source:
        for row in csv.DictReader(source):
            if region is None or row["region"] == region:
                yield row


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("path")
    parser.add_argument("--region")
    args = parser.parse_args(argv)

    for row in rows(args.path, args.region):
        print(",".join(row.values()))


if __name__ == "__main__":
    main()
