# Secrets

This directory is for SOPS-encrypted YAML files.

Setup:
- On the host, derive an age recipient: `ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub`
- Add that recipient to `.sops.yaml` (replace `REPLACE_WITH_AGE_PUBLIC_KEY`).
- Encrypt `secrets/secrets.yaml` in-place once you add values.

Password hashes:
- Generate a SHA-512 hash with `mkpasswd -m sha-512` or `openssl passwd -6`.
- Store the hashes under `root-password` and `kra3-password`.

Example encryption command:

```
sops --encrypt --in-place secrets/secrets.yaml
```
