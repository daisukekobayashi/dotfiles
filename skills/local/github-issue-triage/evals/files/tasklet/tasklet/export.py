import csv


def write_csv(store, stream):
    writer = csv.writer(stream)
    writer.writerow(["title", "done"])
    for task in store.tasks():
        writer.writerow([task["title"], task["done"]])
