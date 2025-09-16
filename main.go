package main

import (
	"context"
	"fmt"
	"log"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/cofogo/esro-ftp-trigger/internal"
	"github.com/cofogo/esro-ftp-trigger/internal/config"
	"github.com/cofogo/esro-ftp-trigger/internal/httpmtls"
)

// S3Event represents the S3 upload event data
type S3Event struct {
	Bucket string `json:"bucket"`
	Key    string `json:"key"`
	Region string `json:"region"`
	S3Path string `json:"s3_path"`
}

// ScanRequest represents the payload to send to the /scan endpoint
type ScanRequest struct {
	S3Path string `json:"s3_path"`
}

func handler(ctx context.Context, event S3Event) error {
	fmt.Printf("Processing S3 upload:\n")
	fmt.Printf("Bucket: %s\n", event.Bucket)
	fmt.Printf("Key: %s\n", event.Key)
	fmt.Printf("Region: %s\n", event.Region)
	fmt.Printf("S3 Path: %s\n", event.S3Path)

	// Load configuration
	cfg := config.Load("")

	// Determine S3 path if not provided in event
	s3Path := event.S3Path
	if s3Path == "" {
		s3Path = fmt.Sprintf("s3://%s/%s", event.Bucket, event.Key)
	}

	// Create HTTP client with mTLS
	client, err := httpmtls.NewClient(
		cfg.Certificates.AWSBucket,
		cfg.Certificates.AWSRegion,
		cfg.Certificates.MTLSSubdir,
		cfg.DataDir,
		cfg.ESRO.BaseURL,
	)
	if err != nil {
		log.Printf("Failed to create HTTP client: %v", err)
		return fmt.Errorf("creating HTTP client: %w", err)
	}

	// Prepare scan request
	scanReq := ScanRequest{
		S3Path: s3Path,
	}

	// Call the /scan endpoint
	fmt.Printf("Calling /scan endpoint with S3 path: %s\n", s3Path)
	response, err := client.Post(ctx, "/scan", scanReq)
	if err != nil {
		log.Printf("Failed to call /scan endpoint: %v", err)
		return fmt.Errorf("calling /scan endpoint: %w", err)
	}

	fmt.Printf("Scan response received: %s\n", string(response))
	return nil
}

func main() {
	if internal.IsDebugMode() {
		fmt.Print("Hello, debug!")
	} else {
		lambda.Start(handler)
	}
}
