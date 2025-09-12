#!/bin/bash
# Enable logging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting FTP server setup..."

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
mkdir -p /opt/ftp/ssl

# Debug: Log the variables being used
echo "FTP Username: ${ftp_username}" >> /var/log/ftp-setup.log
echo "S3 Bucket: ${s3_bucket_name}" >> /var/log/ftp-setup.log
echo "AWS Region: ${aws_region}" >> /var/log/ftp-setup.log

# Generate self-signed SSL certificate for FTPS
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /opt/ftp/ssl/pure-ftpd.key \
    -out /opt/ftp/ssl/pure-ftpd.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=ftp-server"

# Set proper permissions for SSL files
chmod 600 /opt/ftp/ssl/pure-ftpd.key
chmod 644 /opt/ftp/ssl/pure-ftpd.crt

# Create FTP user home directory
mkdir -p /opt/ftp/data/${ftp_username}
chown 1001:1001 /opt/ftp/data/${ftp_username}

# Create temporary script to set up FTP user with hashed password
cat > /opt/ftp/setup-user.sh << 'SCRIPT_EOF'
#!/bin/bash
USERNAME="${ftp_username}"
PASSWORD="${ftp_password}"

# Create user with pure-ftpd tools inside container
docker exec ftp-server pure-pw useradd "$USERNAME" -u 1001 -g 1001 -d /home/ftpusers/"$USERNAME" -m <<< "$PASSWORD"$'\n'"$PASSWORD"
docker exec ftp-server pure-pw mkdb
docker exec ftp-server pure-pw show "$USERNAME"
SCRIPT_EOF

chmod +x /opt/ftp/setup-user.sh

# Debug: Check what user was created
echo "Created user setup script" >> /var/log/ftp-setup.log

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

# Run FTP server container with SSL/TLS support
echo "Starting Pure-FTPd container..." >> /var/log/ftp-setup.log

docker run -d \
  --name ftp-server \
  --restart unless-stopped \
  -p 21:21 \
  -p 990:990 \
  -p 30000-30009:30000-30009 \
  -v /opt/ftp/data:/home/ftpusers \
  -v /opt/ftp/ssl/pure-ftpd.crt:/etc/ssl/private/pure-ftpd.crt \
  -v /opt/ftp/ssl/pure-ftpd.key:/etc/ssl/private/pure-ftpd.key \
  -e PUBLICHOST=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4) \
  -e ADDED_FLAGS="-l puredb:/etc/pure-ftpd/pureftpd.pdb -E -j -R -P $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4) -p 30000:30009 -Y 2" \
  -e TLS_USE_DSAPARAM="false" \
  -e TLS_CIPHER_SUITE="HIGH" \
  stilliard/pure-ftpd:hardened

# Wait for container to start
sleep 15

# Setup the FTP user using pure-pw inside the container
echo "Setting up FTP user..." >> /var/log/ftp-setup.log
/opt/ftp/setup-user.sh >> /var/log/ftp-setup.log 2>&1

# Restart container to ensure all configurations are loaded
echo "Restarting FTP container..." >> /var/log/ftp-setup.log
docker restart ftp-server

sleep 10

echo "FTP server setup completed!" >> /var/log/ftp-setup.log
echo "Container status:" >> /var/log/ftp-setup.log
docker ps >> /var/log/ftp-setup.log
echo "FTP user list:" >> /var/log/ftp-setup.log
docker exec ftp-server pure-pw list >> /var/log/ftp-setup.log 2>&1

# Enable and start the S3 sync service
systemctl enable ftp-s3-sync.service
systemctl start ftp-s3-sync.service

echo "FTP server setup completed!"
