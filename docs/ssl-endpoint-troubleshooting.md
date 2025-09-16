# Troubleshooting and Hardening the OPSI Suit SSL Endpoint

This guide consolidates the moving parts that influence the HTTPS endpoint exposed by the `opsisuit-server` container and collects the remediation actions that have proven to resolve broken TLS handshakes. Follow the sections in order: start with the runtime checks, then decide which remediation path (regenerate the built-in CA, use public certificates, or fall back to a self-signed pair) matches your deployment.

## 1. Understand the default SSL layout

* The Docker compose file publishes three ports from the `opsi-server` service: the JSON-RPC API on `4447/tcp`, the depot service on `4441/tcp`, and the web interface on `4443/tcp`.【F:docker/docker-compose.yml†L44-L56】
* Inside the container, the `opsiconfd` service manages TLS. By default it generates its own certificate authority (CA) and a server certificate under `/etc/opsi/ssl/` and listens on the HTTPS API port defined by `--port` (default `4447`). The management loop automatically checks whether the server certificate needs renewal and restarts workers if it has changed.【F:docker/docker-compose.yml†L44-L56】【F:docker/docker-compose.yml†L57-L73】
* The `scripts/opsisuit-installer.sh` bootstrapper now provisions a self-signed fallback certificate under `data/opsi/etc/opsi/ssl/` whenever no key material exists (or when `--force-config` is used), so the HTTPS listener works right after installation.
* All TLS behaviour is controlled through the `OPSICONFD_*` environment variables. Relevant examples include:
  * `OPSICONFD_SSL_SERVER_CERT_TYPE` (`opsi-ca`, `letsencrypt`, `custom-ca`)
  * `OPSICONFD_SSL_SERVER_CERT`, `OPSICONFD_SSL_SERVER_KEY`, `OPSICONFD_SSL_SERVER_KEY_PASSPHRASE`
  * `OPSICONFD_SSL_TRUSTED_CERTS` (path to the CA bundle used for outbound TLS validation)
  * `OPSICONFD_SSL_SERVER_CERT_SANS` (additional Subject Alternative Names)
  * `OPSICONFD_SKIP_SETUP` (skip parts of the automated setup loop; omit `opsi_ca` and `server_cert` if you want the SSL maintenance tasks to run).

Keep the container’s `OPSI_SERVER_FQDN` and your DNS records in sync. A mismatch is the most common reason for `hostname mismatch` errors when TLS is otherwise healthy.

## 2. Run the baseline diagnostics

1. **Verify that the container is healthy and ports are published**
   ```bash
   docker compose ps opsisuit-server
   docker compose logs -f opsisuit-server
   ```

2. **Confirm that the HTTPS socket is listening inside the container**
   ```bash
   docker compose exec opsisuit-server ss -tlpn | grep 4447
   ```
   (replace `4447` with the effective HTTPS port if it was changed through `OPSICONFD_PORT`).

3. **Inspect the currently active certificate**
   ```bash
   docker compose exec opsisuit-server openssl x509 -in /etc/opsi/ssl/opsiconfd-cert.pem -noout -text |
     sed -n '1,20p'
   ```

4. **Test the handshake from the outside**
   ```bash
   openssl s_client -connect <public-hostname>:4447 -servername <expected-fqdn> -showcerts
   ```
   Pay attention to the certificate chain, SAN list, and validation errors reported by `openssl`.

5. **Check the opsiconfd log for SSL related warnings**
   ```bash
   docker compose exec opsisuit-server grep -i ssl /var/log/opsi/opsiconfd/opsiconfd.log | tail -n 40
   ```
   Messages about missing certificates, passphrase failures, or invalid host names usually pinpoint the root cause.

If diagnostics still point to TLS issues, move to one of the remediation paths below.

## 3. Regenerate the built-in opsi CA and server certificate

Use this path when you rely on the automatically managed certificate (`OPSICONFD_SSL_SERVER_CERT_TYPE=opsi-ca`) and the files in `/etc/opsi/ssl/` became inconsistent (e.g., the CA expired or the passphrase changed).

1. **Back up the current certificate directory** (optional but recommended):
   ```bash
   docker compose exec opsisuit-server tar -C /etc/opsi -czf /tmp/opsi-ssl-backup.tgz ssl
   docker compose cp opsisuit-server:/tmp/opsi-ssl-backup.tgz ./backups/opsi-ssl-backup-$(date +%Y%m%d).tgz
   ```

2. **Trigger the SSL setup tasks explicitly**. The command below skips every setup action except the CA/server certificate regeneration.
   ```bash
   docker compose exec opsisuit-server opsiconfd setup \
     --skip-setup backend redis grafana metric_downsampling samba dhcpd sudoers saml \
     --skip-setup limits users groups files file_permissions log_files
   ```
   The setup runner keeps the SSL tasks enabled because `opsi_ca` and `server_cert` are not part of the skip list.

3. **Reload the service** so that new keys are in use:
   ```bash
   docker compose exec opsisuit-server opsiconfd reload
   ```

4. **Retest the handshake** using the commands from section 2.

If regeneration fails, double-check that the `OPSI_SERVER_FQDN` environment variable matches the certificate’s Common Name and that DNS resolves the name back to the container host.

## 4. Use certificates signed by a public CA (Let’s Encrypt or corporate PKI)

### 4.1 Let’s Encrypt automation

1. Ensure that the public DNS name configured in `OPSI_SERVER_FQDN` resolves to the Docker host and that TCP **port 80** from the Internet terminates on the container (the ACME HTTP-01 challenge needs it). Add a port mapping similar to the one below if your compose file currently exposes only 4443/4447:
   ```yaml
   services:
     opsi-server:
       ports:
         - "80:80"       # Required for Let's Encrypt HTTP-01
         - "4443:4443"
         - "4447:4447"
   ```

2. Add these environment variables to the `opsi-server` service definition:
   ```yaml
   OPSICONFD_SSL_SERVER_CERT_TYPE: letsencrypt
   OPSICONFD_LETSENCRYPT_CONTACT_EMAIL: admin@example.com
   OPSI_SERVER_FQDN: opsi.example.com
   ```

3. Restart the stack:
   ```bash
   docker compose up -d opsi-server
   ```

4. Watch the logs. When the challenge succeeds you should see messages about a new certificate being stored. Validate the HTTPS endpoint as in section 2.

### 4.2 Using an existing corporate certificate

1. Obtain the certificate (`server.crt`), private key (`server.key`), and the issuing CA chain (`ca-bundle.pem`). Make sure the key is either unencrypted or that you know the passphrase.

2. Store the files in the repository, e.g. `configs/ssl/opsiconfd-cert.pem`, `configs/ssl/opsiconfd-key.pem`, and `configs/ssl/opsiconfd-ca.pem`, and mount them read-only into the container:
   ```yaml
   services:
     opsi-server:
       volumes:
         - ../configs/ssl/opsiconfd-cert.pem:/etc/opsi/ssl/opsiconfd-cert.pem:ro
         - ../configs/ssl/opsiconfd-key.pem:/etc/opsi/ssl/opsiconfd-key.pem:ro
         - ../configs/ssl/opsiconfd-ca.pem:/etc/opsi/ssl/opsiconfd-ca.pem:ro
   ```

3. Export the correct environment variables:
   ```yaml
   OPSICONFD_SSL_SERVER_CERT_TYPE: custom-ca
   OPSICONFD_SSL_SERVER_CERT: /etc/opsi/ssl/opsiconfd-cert.pem
   OPSICONFD_SSL_SERVER_KEY: /etc/opsi/ssl/opsiconfd-key.pem
   OPSICONFD_SSL_SERVER_KEY_PASSPHRASE: ""          # leave empty if the key is not encrypted
   OPSICONFD_SSL_CA_CERT: /etc/opsi/ssl/opsiconfd-ca.pem
   OPSICONFD_SSL_TRUSTED_CERTS: /etc/ssl/certs/ca-certificates.crt
   ```

4. Restart the container and confirm that the new chain is served.

## 5. Generate a self-signed fallback certificate

Use this when you need HTTPS immediately (e.g., in an isolated lab) and neither Let’s Encrypt nor a corporate CA are available. The following steps create a small, local CA and server certificate valid for 825 days.

1. **Create a working directory on the Docker host:**
   ```bash
   mkdir -p configs/ssl
   cd configs/ssl
   ```

2. **Generate the CA key and certificate:**
   ```bash
   openssl genrsa -out opsi-root-ca.key 4096
   openssl req -x509 -new -nodes -key opsi-root-ca.key -sha256 -days 1825 \
     -subj "/CN=OpsiSuit Lab CA" -out opsi-root-ca.crt
   ```

3. **Create the server key and CSR with the correct Subject Alternative Names:**
   ```bash
   cat > san.cnf <<'SAN'
   [req]
   distinguished_name = req_distinguished_name
   req_extensions = v3_req
   prompt = no

   [req_distinguished_name]
   CN = opsi.lab.local

   [v3_req]
   keyUsage = digitalSignature, keyEncipherment
   extendedKeyUsage = serverAuth
   subjectAltName = @alt_names

   [alt_names]
   DNS.1 = opsi.lab.local
   DNS.2 = opsi.lab
   IP.1 = 192.168.50.20
   SAN

   openssl genrsa -out opsiconfd-selfsigned.key 4096
   openssl req -new -key opsiconfd-selfsigned.key -out opsiconfd.csr -config san.cnf
   ```

4. **Sign the CSR with the local CA:**
   ```bash
   openssl x509 -req -in opsiconfd.csr -CA opsi-root-ca.crt -CAkey opsi-root-ca.key -CAcreateserial \
     -out opsiconfd-selfsigned.crt -days 825 -sha256 -extensions v3_req -extfile san.cnf
   ```

5. **Expose the files to the container** (same volume snippet as in section 4.2) and configure:
   ```yaml
   OPSICONFD_SSL_SERVER_CERT_TYPE: custom-ca
   OPSICONFD_SSL_SERVER_CERT: /etc/opsi/ssl/opsiconfd-selfsigned.crt
   OPSICONFD_SSL_SERVER_KEY: /etc/opsi/ssl/opsiconfd-selfsigned.key
   OPSICONFD_SSL_CA_CERT: /etc/opsi/ssl/opsi-root-ca.crt
   ```

6. **Distribute the CA certificate (`opsi-root-ca.crt`) to every client** that should trust the endpoint.

## 6. Quick checklist when TLS still fails

* Does the certificate’s SAN list contain the exact hostname used by clients?
* Does DNS resolve that hostname to the Docker host and back again (reverse lookup)?
* Did you mount the certificate files read-only and with permissions that allow the `opsiconfd` process to read them (`640` or `600`)?
* Are there stale secrets (`OPSICONFD_SSL_SERVER_KEY_PASSPHRASE`) cached in the container environment? Restart the service to clear them.
* If Let’s Encrypt issuance fails, inspect `/var/lib/opsiconfd/letsencrypt` for challenge logs.
* For self-signed deployments, remember to import the CA on every opsi client as well as on the administrator’s browser.

Following the above steps restores the SSL endpoint in the majority of real-world failure modes—certificate expiry, hostname drift, missing trust anchors, or accidental deletion of `/etc/opsi/ssl/`.
