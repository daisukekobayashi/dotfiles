import contextlib
import io
import unittest

import export


def run(*argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        export.main(["orders.csv", *argv])
    return out.getvalue().splitlines()


class ExportTest(unittest.TestCase):
    def test_prints_every_row(self):
        self.assertEqual(len(run()), 3)

    def test_region_filters_rows(self):
        self.assertEqual([line[0] for line in run("--region", "east")], ["1", "3"])


if __name__ == "__main__":
    unittest.main()
