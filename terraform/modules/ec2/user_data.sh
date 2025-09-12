# --- Prepare local FTP home ---------------------------------------------------
mkdir -p /home/ftpusers/${ftp_username}
chown -R 1000:1000 /home/ftpusers/${ftp_username}

# --- Run FTP container --------------------------------------------------------
echo "Starting FTP server container with local home..." >> /var/log/ftp-setup.log
docker rm -f s3-ftp >/dev/null 2>&1 || true

docker run -d \
  --name s3-ftp \
  --restart unless-stopped \
  -v /home/ftpusers:/home/ftpusers \
  -p 21:21 \
  -p 50000-50050:50000-50050 \
  -e FTP_USER_NAME=${ftp_username} \
  -e FTP_USER_PASS=${ftp_password} \
  -e FTP_USER_HOME=/home/ftpusers/${ftp_username} \
  stilliard/pure-ftpd:hardened \
  /run.sh -p 50000:50050 -P $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# --- Background sync to S3 ---------------------------------------------------
cat >/usr/local/bin/s3-sync.sh <<'EOF'
#!/bin/bash
while true; do
  aws s3 sync /home/ftpusers/${ftp_username} s3://${s3_bucket_name}/ \
    --region ${aws_region} --exact-timestamps
  # Remove local files after syncing
  find /home/ftpusers/${ftp_username} -type f -delete
  sleep 10
done
EOF
chmod +x /usr/local/bin/s3-sync.sh
nohup /usr/local/bin/s3-sync.sh >> /var/log/ftp-sync.log 2>&1 &
