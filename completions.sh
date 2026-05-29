#!/bin/bash

curl -s -X POST "http://snow-ai-server.reindeer-pinecone.ts.net:9292/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
  "messages": [
    {"role": "user", "content": "what is the capitol of france?"}
  ],
  "stream": true,
  "return_progress": false,
  "model": "qwen3.6-27b",
  "reasoning_format": "auto",
  "backend_sampling": false,
  "timings_per_token": false,
  "stream_options": {
    "include_usage": true
  }
}'
