Aws.config.update(
  region: "ap-northeast-1",
  endpoint: ENV.fetch("DYNAMODB_ENDPOINT", "http://localhost:8000"),
  credentials: Aws::Credentials.new("dummy", "dummy")
)
