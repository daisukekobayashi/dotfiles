import json
import os
import sys

PATH = os.path.expanduser("~/.tasklet.json")


class Store:
    def __init__(self, path):
        self.path = path
        self.stream = sys.stdout

    def tasks(self):
        if not os.path.exists(self.path):
            return []
        with open(self.path) as handle:
            return json.load(handle)

    def add(self, title):
        tasks = self.tasks() + [{"title": title, "done": False}]
        with open(self.path, "w") as handle:
            json.dump(tasks, handle)


def open_store():
    return Store(PATH)
