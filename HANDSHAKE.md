### SUMMARIZE
Middleware checks confirm that:

DNS resolution and TCP connectivity to secweb-stest3.dev.echonet:443 (10.118.107.252) are working correctly.
TLS 1.2 connectivity and certificate validation are successful.
AES128-GCM-SHA256 works successfully.
ECDHE-RSA-AES128-GCM-SHA256 and ECDHE-RSA-AES256-GCM-SHA384 are rejected with TLS alert 40 (handshake_failure).
TLS 1.3 is rejected with protocol_version (alert 70).

The issue is therefore related to TLS protocol/cipher negotiation towards the AVI endpoint 10.118.107.252, rather than basic network connectivity or certificate validation.