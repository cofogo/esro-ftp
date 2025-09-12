package main

import (
	"context"
	"fmt"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/cofogo/esro-ftp-trigger/internal"
)

// S3Event represents the S3 upload event data
type S3Event struct {
	Bucket string `json:"bucket"`
	Key    string `json:"key"`
	Region string `json:"region"`
	S3Path string `json:"s3_path"`
}

func handler(ctx context.Context, event S3Event) error {
	fmt.Printf("Hello, World! Processing S3 upload:\n")
	fmt.Printf("Bucket: %s\n", event.Bucket)
	fmt.Printf("Key: %s\n", event.Key)
	fmt.Printf("Region: %s\n", event.Region)
	fmt.Printf("S3 Path: %s\n", event.S3Path)
	return nil
}

func main() {
	if internal.IsDebugMode() {
		fmt.Print("Hello, debug!")
	} else {
		lambda.Start(handler)
	}
}
