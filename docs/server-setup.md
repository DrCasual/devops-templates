# Server setup: self-hosted runner and deploy folders

GitHub's own runners can't reach a server on a home network. Instead, a small agent (the *self-hosted runner*) runs on the server. It connects out to GitHub and picks up deploy jobs, so no port is opened on the router.

The steps below use two terminal windows:
- **Terminal 1:** your Mac.
- **Terminal 2:** an ssh session on the server that is already open.

Replace `OWNER/REPO`, `APP`, and the domain names with the project's values.

## 1. Runner user (once per server)

**Terminal 2**
```bash
sudo useradd -m -s /bin/bash github-runner
sudo usermod -aG docker github-runner
```

> Membership of the `docker` group gives that user root-level power on the server. Only connect **private** repositories to this runner.

## 2. Runner per repository

A personal GitHub account registers runners per repository, so every project gets its own runner folder on the same server. (A free GitHub *organization* could share one runner across all repos later.)

In GitHub, go to the repository → **Settings → Actions → Runners → New self-hosted runner → Linux**. Copy the **token** from the `./config.sh` line on that page. It is valid for one hour.

**Terminal 2**
```bash
REPO=OWNER/REPO
DIR=/opt/actions-runner/$(basename "$REPO" | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')
VERSION=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | sed -n 's/.*"tag_name": "v\([^"]*\)".*/\1/p')
sudo mkdir -p "$DIR" && sudo chown github-runner: "$DIR"
sudo -u github-runner bash -c "cd $DIR && curl -fsSL -o runner.tgz https://github.com/actions/runner/releases/download/v$VERSION/actions-runner-linux-$ARCH-$VERSION.tar.gz && tar xzf runner.tgz && rm runner.tgz"
```
```bash
read -rsp "Runner token: " TOKEN && echo
sudo -u github-runner bash -c "cd $DIR && ./config.sh --unattended --url https://github.com/$REPO --token $TOKEN --name home-server --labels home-server --replace"
cd "$DIR" && sudo ./svc.sh install github-runner && sudo ./svc.sh start
```

The runner now shows as *Idle* under Settings → Actions → Runners. It starts by itself after a reboot.

## 3. Deploy folder per environment

Each environment (staging, production) has its own folder, `.env`, data and database.

**Terminal 2**
```bash
DIR=/opt/APP.example.be          # e.g. /opt/staging.APP.example.be for staging
sudo mkdir -p "$DIR"/backups "$DIR"/.deploy
sudo nano "$DIR"/.env            # secrets + COMPOSE_PROJECT_NAME=APP (or APP-staging)
sudo chown github-runner: "$DIR" "$DIR"/.env "$DIR"/backups "$DIR"/.deploy
sudo chmod 600 "$DIR"/.env
```

Give every environment its own `COMPOSE_PROJECT_NAME` and its own host port in `.env`, so staging and production can run side by side.

Data folders (uploads, database) get the owner that the **container** expects, not `github-runner`. The project's README says which one that is.

## 4. nginx and HTTPS per hostname

**Terminal 2**
```bash
HOST=staging.APP.example.be PORT=8091
sudo tee /etc/nginx/sites-available/$HOST >/dev/null <<EOF
server {
    server_name $HOST;
    client_max_body_size 25m;
    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
sudo ln -sf /etc/nginx/sites-available/$HOST /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d $HOST
```

Add an A record for the hostname at the DNS provider first, pointing to the same IP as the other sites.

## Useful commands on the server

```bash
cd /opt/APP.example.be
sudo -u github-runner docker compose ps
sudo -u github-runner docker compose logs -f app
cat .deploy/current       # running image
cat .deploy/history       # every deploy
ls backups/               # latest backups (kept: 14)
```
