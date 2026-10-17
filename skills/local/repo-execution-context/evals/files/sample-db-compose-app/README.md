# Sample App With a Containerized Database

The application and its tests run on the host. Compose manages PostgreSQL only:

```sh
docker compose up -d db
```

With the database already available, run tests from the repository directory:

```sh
python3 -m unittest discover
```
