# output "instance_id" {
#   description = "ID of the FTP server EC2 instance"
#   value       = aws_instance.ftp_server.id
# }

output "public_ip" {
  description = "Public IP address of the FTP server"
  value       = aws_instance.ftp_server.public_ip
}

output "elastic_ip" {
  description = "Elastic IP address of the FTP server"
  value       = aws_eip.ftp_server.public_ip
}

output "private_ip" {
  description = "Private IP address of the FTP server"
  value       = aws_instance.ftp_server.private_ip
}

output "security_group_id" {
  description = "Security group ID for the FTP server"
  value       = aws_security_group.ftp_server.id
}

output "ftp_endpoint" {
  description = "FTP server endpoint"
  value       = "ftp://${aws_instance.ftp_server.public_ip}:21"
}

output "ftp_domain_endpoint" {
  description = "FTP server domain endpoint (if DNS record is created)"
  value       = var.route53_zone_name != "" ? "ftp://${var.ftp_domain}:21" : "DNS record not created - no zone name provided"
}

output "dns_record_created" {
  description = "Whether DNS record was created (automatic based on route53_zone_name)"
  value       = var.route53_zone_name != ""
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i /path/to/your/key.pem ec2-user@${aws_instance.ftp_server.public_ip}"
}
