#!/usr/bin/env python3
import json
import sys


messages = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
    {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
    {
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {"name": "search_issues", "arguments": {"query": "phase 11"}},
    },
    {
        "jsonrpc": "2.0",
        "id": 4,
        "method": "tools/call",
        "params": {"name": "delete_repository", "arguments": {"repo": "fake/repo"}},
    },
    {"jsonrpc": "2.0", "id": 5, "method": "resources/list", "params": {}},
    {
        "jsonrpc": "2.0",
        "id": 6,
        "method": "resources/read",
        "params": {"uri": "repo://docs/README.md"},
    },
    {"jsonrpc": "2.0", "id": 7, "method": "prompts/list", "params": {}},
    {
        "jsonrpc": "2.0",
        "id": 8,
        "method": "prompts/get",
        "params": {"name": "review", "arguments": {"note": "fake_secret_value"}},
    },
    {
        "jsonrpc": "2.0",
        "id": 9,
        "method": "sampling/createMessage",
        "params": {
            "model": "local",
            "messages": [
                {
                    "role": "user",
                    "content": {"type": "text", "text": "fake_secret_value"},
                }
            ],
        },
    },
]

for message in messages:
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
sys.stdout.flush()
