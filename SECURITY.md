# GrantTap security contract

GrantTap routes agent traffic through an untrusted relay. The Cloudflare Worker
is allowed to store and forward only authenticated ciphertext and operational
metadata; it has no application decryption key.

## Encryption layers

1. Each Mac↔iPhone pairing has unique Curve25519 keys generated locally. NaCl
   `box` authenticates and encrypts every protocol payload before relay upload.
2. Pairing hand-off uses a random 128-bit mailbox id and an independent random
   256-bit transfer key. The HTTP path contains only the mailbox id; the key is
   carried by the QR/manual token and never reaches Cloudflare.
3. Each attached Codex or Claude Code task has an independent random 256-bit
   key. Task content is secretbox-encrypted again inside the device box. A key
   from task A cannot decrypt task B.
4. iOS stores device and task keys in device-only Keychain. The Mac stores its
   local task-key map with mode `0600`. Keys and plaintext are never Worker
   variables, Durable Object values, logs, analytics, or APNs fields.

Plaintext exists only at an authorized endpoint: the agent Mac and an iPhone
that received the key for that specific task. Every route between them remains
authenticated ciphertext while it crosses the app transport, the network,
Cloudflare, Durable Objects, and APNs.

## What a relay/database compromise exposes

Ciphertext, opaque room/mailbox and delivery ids, routing roles, IP addresses,
timing/expiry, sizes, APNs device token/environment, and a content-neutral wake
flag. APNs contains no task kind, request id, delivery id, title, prompt,
command, path, or response. The APNs provider key can sign notifications; it
cannot decrypt GrantTap traffic.

## Isolation and its honest limit

Another pairing/device has different endpoint keys. Separately, disclosure of
one task key does not open another task. A device can decrypt every task key
that was explicitly granted to it, but possession of that device alone cannot
decrypt another pairing or a task whose key was never granted to it. If the
same device is explicitly granted two tasks, it is an authorized endpoint for
both. The agent Mac necessarily has access to its own local transcripts. Those
authorized endpoint compromises are not a relay-side confidentiality guarantee.
