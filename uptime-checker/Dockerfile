
# Use official Golang image as base
FROM golang:1.22-alpine

# Set working directory inside container
WORKDIR /app

# Copy Go source files into container
COPY ./cmd /app

# Download dependencies
RUN go mod tidy

# Build the Go binary
RUN go build -o app .

# Expose port 8080 for the API
EXPOSE 8080

# Command to run the application
CMD ["./app"]
