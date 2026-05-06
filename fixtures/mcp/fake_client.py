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
]

for message in messages:
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
sys.stdout.flush()
