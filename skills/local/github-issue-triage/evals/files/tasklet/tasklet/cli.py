import argparse

from tasklet import export, storage, terminal


def main(argv=None):
    parser = argparse.ArgumentParser(prog="tasklet")
    commands = parser.add_subparsers(dest="command", required=True)
    add = commands.add_parser("add", help="record a task")
    add.add_argument("title")
    commands.add_parser("list", help="show tasks")
    commands.add_parser("export", help="write tasks as CSV")
    args = parser.parse_args(argv)
    store = storage.open_store()
    if args.command == "add":
        store.add(args.title)
    elif args.command == "list":
        terminal.print_tasks(store.tasks())
    else:
        export.write_csv(store, terminal.output_stream(store))
    return 0
