写一个本地开发用的 docker-compose.yml：postgres、redis，加一个 app 服务（镜像用 example/app:dev 即可）。app 通过环境变量拿到数据库密码、redis 密码，以及一个第三方短信服务的 API token。再配一个 .env.example，把这三个值都填上示例值，让人复制成 .env 后能直接 docker compose up，不用再改。
