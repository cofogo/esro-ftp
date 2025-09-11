package main

import (
	"context"
	"fmt"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/cofogo/esro-ftp-trigger/internal"
)

func handler(ctx context.Context) error {
	fmt.Print("Hello, World!")
	return nil
}

func main() {
	if internal.IsDebugMode() {
		fmt.Print("Hello, debug!")
	} else {
		lambda.Start(handler)
	}
}
