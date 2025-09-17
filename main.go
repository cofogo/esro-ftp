package main

import (
	"context"
	"fmt"
	"log"
	"path/filepath"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/cofogo/esro-ftp-trigger/internal"
	"github.com/cofogo/esro-ftp-trigger/internal/awsutil"
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
	S3Path string `json:"s3Path"`
}

// moveFileToManagementBucket copies a file from the source bucket to esro-management-data/uploads
func moveFileToManagementBucket(ctx context.Context, sourceBucket, sourceKey, region string) error {
	// Create AWS client
	awsClient, err := awsutil.New(ctx, sourceBucket, region)
	if err != nil {
		return fmt.Errorf("failed to create AWS client: %w", err)
	}

	// Create destination key with uploads prefix
	destKey := fmt.Sprintf("uploads/%s", filepath.Base(sourceKey))
	destBucket := "esro-management-data"

	// Copy the file to the management bucket
	err = awsClient.CopyS3Object(ctx, sourceBucket, sourceKey, destBucket, destKey)
	if err != nil {
		return fmt.Errorf("failed to copy file: %w", err)
	}

	fmt.Printf("Successfully copied s3://%s/%s to s3://%s/%s\n",
		sourceBucket, sourceKey, destBucket, destKey)
	return nil
}

func handler(ctx context.Context, event S3Event) error {
	fmt.Printf("Processing S3 upload:\n")
	fmt.Printf("Bucket: %s\n", event.Bucket)
	fmt.Printf("Key: %s\n", event.Key)
	fmt.Printf("Region: %s\n", event.Region)
	fmt.Printf("S3 Path: %s\n", event.S3Path)

	// Load configuration
	cfg := config.Load("")

	// Move the file to the esro-management-data bucket
	fmt.Printf("Moving file to esro-management-data bucket...\n")
	err := moveFileToManagementBucket(ctx, event.Bucket, event.Key, event.Region)
	if err != nil {
		log.Printf("Failed to move file to management bucket: %v", err)
		return fmt.Errorf("moving file to management bucket: %w", err)
	}

	// Create S3 path pointing to the new location
	newKey := fmt.Sprintf("uploads/%s", filepath.Base(event.Key))
	s3Path := fmt.Sprintf("s3://esro-management-data/%s", newKey)
	fmt.Printf("File moved successfully. New S3 path: %s\n", s3Path)

	// Create HTTP client with mTLS
	client, err := httpmtls.NewClient(
		cfg.AWS.CertsBucket,
		cfg.AWS.Region,
		cfg.AWS.MTLSSubdir,
		cfg.API.URL,
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
