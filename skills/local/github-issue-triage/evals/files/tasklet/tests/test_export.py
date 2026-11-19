import io
import unittest

from tasklet import export


class FakeStore:
    def tasks(self):
        return [{"title": "a, b", "done": False}]


class ExportTests(unittest.TestCase):
    def test_writes_header_and_rows(self):
        stream = io.StringIO()
        export.write_csv(FakeStore(), stream)
        self.assertEqual(stream.getvalue().splitlines()[0], "title,done")


if __name__ == "__main__":
    unittest.main()
