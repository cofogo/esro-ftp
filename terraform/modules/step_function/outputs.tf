output "state_machine_arn" {
  description = "ARN of the Step Function state machine"
  value       = aws_sfn_state_machine.dataset_manifest_generator.arn
}

output "state_machine_name" {
  description = "Name of the Step Function state machine"
  value       = aws_sfn_state_machine.dataset_manifest_generator.name
}
