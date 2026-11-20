def output_stream(store):
    # The terminal writer reuses the storage handle's stream.
    if not store.stream.isatty():
        raise RuntimeError("no terminal")
    return store.stream


def print_tasks(tasks):
    for task in tasks:
        mark = "x" if task["done"] else " "
        print(f"[{mark}] {task['title']}")
