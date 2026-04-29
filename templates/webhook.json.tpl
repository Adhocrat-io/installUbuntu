[
  {
    "id": "gh-deploy",
    "execute-command": "/usr/local/bin/dispatch-deploy.sh",
    "command-working-directory": "/tmp",
    "response-message": "Dispatching deploy…",
    "include-command-output-in-response": false,
    "pass-arguments-to-command": [
      { "source": "payload", "name": "ref" }
    ],
    "trigger-rule": {
      "and": [
        {
          "match": {
            "type": "payload-hmac-sha256",
            "secret": "{{HMAC_SECRET}}",
            "parameter": { "source": "header", "name": "X-Hub-Signature-256" }
          }
        },
        {
          "match": {
            "type": "value",
            "value": "push",
            "parameter": { "source": "header", "name": "X-GitHub-Event" }
          }
        }
      ]
    }
  }
]
