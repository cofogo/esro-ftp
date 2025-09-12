#!/bin/bash
yum update -y

# Install Docker
yum install -y docker
service docker start
usermod -a -G docker ec2-user

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Create directories for FTP server
mkdir -p /opt/ftp/data
mkdir -p /opt/ftp/config

# Create FTP user configuration
cat > /opt/ftp/config/users.conf << EOF
${ftp_username}|${ftp_password}|/ftp|10001
EOF

# Create script to sync FTP uploads to S3
cat > /opt/ftp/sync-to-s3.sh << 'EOF'
#!/bin/bash
WATCH_DIR="/opt/ftp/data"
S3_BUCKET="${s3_bucket_name}"
AWS_REGION="${aws_region}"

# Monitor directory for new files and sync to S3
inotifywait -m -r -e create,moved_to "$WATCH_DIR" --format '%w%f' |
while read FILE; do
    echo "New file detected: $FILE"
    # Remove the base path to get relative path
    RELATIVE_PATH=$${FILE#$WATCH_DIR/}
    echo "Syncing $RELATIVE_PATH to S3..."
    aws s3 cp "$FILE" "s3://$S3_BUCKET/$RELATIVE_PATH" --region "$AWS_REGION"
    if [ $? -eq 0 ]; then
        echo "Successfully uploaded $RELATIVE_PATH to S3"
    else
        echo "Failed to upload $RELATIVE_PATH to S3"
    fi
done
EOF

chmod +x /opt/ftp/sync-to-s3.sh

# Install inotify-tools for file monitoring
yum install -y inotify-tools

# Create systemd service for S3 sync
cat > /etc/systemd/system/ftp-s3-sync.service << EOF
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

# Run FTP server container
docker run -d \
  --name ftp-server \
  --restart unless-stopped \
  -p 21:21 \
  -p 30000-30009:30000-30009 \
  -v /opt/ftp/data:/ftp \
  -v /opt/ftp/config/users.conf:/etc/pure-ftpd/passwd/pureftpd.passwd \
  -e PUBLICHOST=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4) \
  -e ADDED_FLAGS="-j -R -p 30000:30009" \
  stilliard/pure-ftpd:hardened

# Enable and start the S3 sync service
systemctl enable ftp-s3-sync.service
systemctl start ftp-s3-sync.service

echo "FTP server setup completed!"
