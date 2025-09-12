#!/bin/bash
set -Eeuo pipefail
# Enable logging
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting FTP server setup..."

# --- Base packages ------------------------------------------------------------
yum update -y
yum install -y docker unzip inotify-tools
systemctl enable docker
systemctl start docker
usermod -a -G docker ec2-user || true

# --- AWS CLI v2 ---------------------------------------------------------------
if ! command -v aws >/dev/null 2>&1; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
  unzip -o /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
fi

# --- Directories --------------------------------------------------------------
mkdir -p /opt/ftp/data
mkdir -p /opt/ftp/config
mkdir -p /opt/ftp/ssl

# --- Debug: variables ---------------------------------------------------------
echo "[$(date -Is)] FTP Username: ${ftp_username}"   >> /var/log/ftp-setup.log
echo "[$(date -Is)] S3 Bucket:    ${s3_bucket_name}" >> /var/log/ftp-setup.log
echo "[$(date -Is)] AWS Region:    ${aws_region}"     >> /var/log/ftp-setup.log

# --- TLS certificate (PEM expected by pure-ftpd) ------------------------------
CRT=/opt/ftp/ssl/pure-ftpd.crt
KEY=/opt/ftp/ssl/pure-ftpd.key
PEM=/opt/ftp/ssl/pure-ftpd.pem

if [ ! -s "$CRT" ] || [ ! -s "$KEY" ]; then
  echo "Generating self-signed cert..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$KEY" \
    -out "$CRT" \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=ftp-server"
fi

cat "$KEY" "$CRT" > "$PEM"
chmod 600 "$PEM"
chmod 600 "$KEY"
chmod 644 "$CRT"

# --- Start/replace Pure-FTPd container ---------------------------------------
echo "Starting Pure-FTPd container..." >> /var/log/ftp-setup.log
PUBLIC_IP=$(curl -fsS http://169.254.169.254/latest/meta-data/public-ipv4 || echo "0.0.0.0")

# Remove old container if present
docker rm -f ftp-server >/dev/null 2>&1 || true

docker run -d \
  --name ftp-server \
  --restart unless-stopped \
  -p 21:21 \
  -p 990:990 \
  -p 30000-30009:30000-30009 \
  -v /opt/ftp/data:/home/ftpusers \
  -v /opt/ftp/ssl/pure-ftpd.pem:/etc/ssl/private/pure-ftpd.pem \
  -e TLS=2 \
  -e PUBLICHOST="${PUBLIC_IP}" \
  -e ADDED_FLAGS="-l puredb:/etc/pure-ftpd/pureftpd.pdb -E -j -R -P ${PUBLIC_IP} -p 30000:30009 -Y 2" \
  stilliard/pure-ftpd:hardened

# --- Wait a moment for daemon to come up -------------------------------------
sleep 8

# --- Ensure host dir ownership matches container's ftpuser:ftpgroup ----------
FTP_UID=$(docker exec ftp-server id -u ftpuser)
FTP_GID=$(docker exec ftp-server id -g ftpuser)
echo "Container ftpuser uid/gid: ${FTP_UID}/${FTP_GID}" >> /var/log/ftp-setup.log

# Create the user home dir on host (owned by container's ftp user/group)
mkdir -p "/opt/ftp/data/${ftp_username}"
chown -R "${FTP_UID}:${FTP_GID}" "/opt/ftp/data"

# --- Create/refresh pure-pw user inside container ----------------------------
# Use names (ftpuser/ftpgroup) instead of hardcoded numeric IDs to avoid mismatch
echo "Setting up FTP user ${ftp_username}..." >> /var/log/ftp-setup.log

# If the user already exists, remove it first to ensure password/home are correct
if docker exec ftp-server pure-pw show "${ftp_username}" >/dev/null 2>&1; then
  docker exec ftp-server pure-pw userdel "${ftp_username}" || true
fi

printf "%s\n%s\n" "${ftp_password}" "${ftp_password}" | docker exec -i ftp-server \
  pure-pw useradd "${ftp_username}" -u ftpuser -g ftpgroup -d "/home/ftpusers/${ftp_username}" -m

docker exec ftp-server pure-pw mkdb
docker exec ftp-server pure-pw show "${ftp_username}" >> /var/log/ftp-setup.log 2>&1

# --- Sanity: ensure Pure-FTPd actually picked up TLS -------------------------
docker logs --since 1m ftp-server | egrep -i 'TLS|pem|cert' || true

# --- S3 Sync: watcher script --------------------------------------------------
cat >/opt/ftp/sync-to-s3.sh <<'EOF'
#!/bin/bash
set -Eeuo pipefail
WATCH_DIR="/opt/ftp/data"
S3_BUCKET="${s3_bucket_name}"
AWS_REGION="${aws_region}"

inotifywait -m -r -e create,moved_to "$WATCH_DIR" --format '%w%f' | while read -r FILE; do
  echo "[$(date -Is)] New file detected: $FILE"
  RELATIVE_PATH="${FILE#${WATCH_DIR}/}"
  echo "[$(date -Is)] Syncing $RELATIVE_PATH to s3://$S3_BUCKET/$RELATIVE_PATH ..."
  if aws s3 cp "$FILE" "s3://$S3_BUCKET/$RELATIVE_PATH" --region "$AWS_REGION"; then
    echo "[$(date -Is)] Successfully uploaded $RELATIVE_PATH"
  else
    echo "[$(date -Is)] Failed to upload $RELATIVE_PATH"
  fi
done
EOF
chmod +x /opt/ftp/sync-to-s3.sh

# --- Systemd unit for S3 sync -------------------------------------------------
cat >/etc/systemd/system/ftp-s3-sync.service <<'EOF'
[Unit]
Description=FTP to S3 Sync Service
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/opt/ftp/sync-to-s3.sh
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ftp-s3-sync.service
systemctl start ftp-s3-sync.service

# --- Final restart to ensure latest puredb is loaded --------------------------
docker restart ftp-server
sleep 5

# --- Diagnostics --------------------------------------------------------------
echo "FTP server setup completed!" | tee -a /var/log/ftp-setup.log
echo "Container status:"           | tee -a /var/log/ftp-setup.log
docker ps                          | tee -a /var/log/ftp-setup.log
echo "FTP user list:"              | tee -a /var/log/ftp-setup.log
docker exec ftp-server pure-pw list | tee -a /var/log/ftp-setup.log
echo "Done."
