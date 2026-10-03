#!/usr/bin/env python3
"""Reference implementation of the medas notary commitment hash (protocol v1).

Standard library only. Normative definition: docs/notary-spec.md.

    content_sha256 = SHA-256(payload)        payload: the content, at least 1 byte
    preimage = b"medas-notary/v1"            15 bytes ASCII
             || uint8(len(creator_bytes))
             || creator_bytes                raw address bytes (20 or 32)
             || salt                         exactly 32 bytes
             || content_sha256               exactly 32 bytes
    hash     = SHA-256(preimage)

Usage:
    notary_hash.py salt
        print a fresh 32-byte salt (hex) from the OS CSPRNG
    notary_hash.py hash --creator ADDR --salt HEX (--payload STR | --payload-file F | --payload-hex HEX)
        print the commitment hash (hex)
    notary_hash.py hash --creator ADDR --salt HEX --content-sha256 HEX
        same, from the content digest alone (the content itself is not needed)
    notary_hash.py content-sha256 (--payload STR | --payload-file F | --payload-hex HEX)
        print SHA-256 of the content (hex)
    notary_hash.py canonical-json FILE
        print FILE as canonical JSON (RFC 8785 subset, see canonical_json)
    notary_hash.py vectors [FILE]
        verify the test vectors in FILE (default: the testdata file)
    notary_hash.py make-vectors
        print the test vectors as JSON (used to create the testdata file)
"""

import argparse
import hashlib
import json
import os
import secrets
import sys

DOMAIN = b"medas-notary/v1"
SALT_LEN = 32
DIGEST_LEN = 32
ADDRESS_LENGTHS = (20, 32)
HRP = "medas"

DEFAULT_VECTORS = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "x", "medasdigital", "types", "testdata", "notary_hash_vectors.json",
)

# --------------------------------------------------------------------------
# bech32 (BIP-173). Cosmos addresses use the original bech32 checksum
# (constant 1), not bech32m. The 90 character limit of BIP-173 is kept; a
# 32-byte address with the "medas" prefix has 64 characters.

CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"


def _polymod(values):
    gen = (0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3)
    chk = 1
    for v in values:
        top = chk >> 25
        chk = (chk & 0x1FFFFFF) << 5 ^ v
        for i in range(5):
            chk ^= gen[i] if ((top >> i) & 1) else 0
    return chk


def _hrp_expand(hrp):
    return [ord(c) >> 5 for c in hrp] + [0] + [ord(c) & 31 for c in hrp]


def _convertbits(data, frombits, tobits, pad):
    acc, bits, out = 0, 0, []
    maxv = (1 << tobits) - 1
    for value in data:
        if value < 0 or value >> frombits:
            raise ValueError("invalid value for bit conversion")
        acc = (acc << frombits) | value
        bits += frombits
        while bits >= tobits:
            bits -= tobits
            out.append((acc >> bits) & maxv)
    if pad:
        if bits:
            out.append((acc << (tobits - bits)) & maxv)
    elif bits >= frombits or ((acc << (tobits - bits)) & maxv):
        raise ValueError("invalid padding")
    return out


def bech32_decode(addr):
    """Return (hrp, data bytes) of a bech32 string, raising ValueError."""
    if any(ord(c) < 33 or ord(c) > 126 for c in addr):
        raise ValueError("invalid character")
    if addr.lower() != addr and addr.upper() != addr:
        raise ValueError("mixed case")
    addr = addr.lower()
    pos = addr.rfind("1")
    if pos < 1 or pos + 7 > len(addr) or len(addr) > 90:
        raise ValueError("invalid separator position or length")
    hrp, data_part = addr[:pos], addr[pos + 1:]
    if any(c not in CHARSET for c in data_part):
        raise ValueError("invalid data character")
    data = [CHARSET.find(c) for c in data_part]
    if _polymod(_hrp_expand(hrp) + data) != 1:
        raise ValueError("invalid checksum")
    return hrp, bytes(_convertbits(data[:-6], 5, 8, False))


def bech32_encode(hrp, raw):
    data = _convertbits(raw, 8, 5, True)
    values = _hrp_expand(hrp) + data
    polymod = _polymod(values + [0] * 6) ^ 1
    checksum = [(polymod >> 5 * (5 - i)) & 31 for i in range(6)]
    return hrp + "1" + "".join(CHARSET[d] for d in data + checksum)


# --------------------------------------------------------------------------
# commitment hash


def address_bytes(creator, hrp=HRP):
    got_hrp, raw = bech32_decode(creator)
    if got_hrp != hrp:
        raise ValueError(f"address prefix {got_hrp!r}, expected {hrp!r}")
    if len(raw) not in ADDRESS_LENGTHS:
        raise ValueError(f"address has {len(raw)} bytes, expected 20 or 32")
    return raw


def content_sha256(payload):
    if len(payload) < 1:
        raise ValueError("payload must not be empty")
    return hashlib.sha256(payload).digest()


def preimage(creator_raw, salt, digest):
    """digest: SHA-256 of the content (32 bytes), not the content itself."""
    if len(creator_raw) not in ADDRESS_LENGTHS:
        raise ValueError("creator must be 20 or 32 bytes")
    if len(salt) != SALT_LEN:
        raise ValueError("salt must be exactly 32 bytes")
    if len(digest) != DIGEST_LEN:
        raise ValueError("content digest must be exactly 32 bytes")
    return DOMAIN + bytes([len(creator_raw)]) + creator_raw + salt + digest


def commitment_hash_from_digest(creator, salt, digest, hrp=HRP):
    """creator: bech32 string, salt: 32 bytes, digest: SHA-256 of the content -> 32 bytes."""
    return hashlib.sha256(preimage(address_bytes(creator, hrp), salt, digest)).digest()


def commitment_hash(creator, salt, payload, hrp=HRP):
    """creator: bech32 string, salt: 32 bytes, payload: content bytes -> 32 bytes."""
    return commitment_hash_from_digest(creator, salt, content_sha256(payload), hrp)


# --------------------------------------------------------------------------
# canonical JSON (RFC 8785 / JCS) for the subset used by payloads: objects,
# arrays, strings, integers, booleans and null. Floats are rejected, because
# JCS number serialisation (ECMAScript) is not reproduced here; encode
# fractional values as strings or scaled integers instead.


def _reject_floats(value):
    if isinstance(value, float):
        raise ValueError("floats are not supported; use strings or integers")
    if isinstance(value, dict):
        for v in value.values():
            _reject_floats(v)
    elif isinstance(value, list):
        for v in value:
            _reject_floats(v)


def _sort_keys(value):
    # JCS sorts object keys by their UTF-16 code units.
    if isinstance(value, dict):
        return {k: _sort_keys(value[k]) for k in sorted(value, key=lambda k: k.encode("utf-16-be"))}
    if isinstance(value, list):
        return [_sort_keys(v) for v in value]
    return value


def canonical_json(value):
    _reject_floats(value)
    for n in _iter_ints(value):
        if abs(n) > 2**53 - 1:
            raise ValueError("integers beyond 2^53-1 are not interoperable in JSON")
    text = json.dumps(_sort_keys(value), ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    return text.encode("utf-8")


def _iter_ints(value):
    if isinstance(value, bool):
        return
    if isinstance(value, int):
        yield value
    elif isinstance(value, dict):
        for v in value.values():
            yield from _iter_ints(v)
    elif isinstance(value, list):
        for v in value:
            yield from _iter_ints(v)


# --------------------------------------------------------------------------
# test vectors


def _module_address(name, key):
    # Cosmos SDK address.Module(name, key) = sha256(sha256("module") || name || 0x00 || key)
    return hashlib.sha256(hashlib.sha256(b"module").digest() + name.encode() + b"\x00" + key).digest()


def _wasm_contract_address(code_id, instance_id):
    # wasmd BuildContractAddressClassic
    key = code_id.to_bytes(8, "big") + instance_id.to_bytes(8, "big")
    return _module_address("wasm", key)


def make_vectors():
    gov = hashlib.sha256(b"gov").digest()[:20]  # authtypes.NewModuleAddress("gov")
    contract = _wasm_contract_address(1, 1)
    cases = [
        {
            "name": "20-byte account address, ASCII JSON payload",
            "creator_raw": gov,
            "salt": bytes(range(32)),
            "payload": canonical_json({
                "epoch": "2026-10-01T00:00:00Z",
                "object": "2024 YR4",
                "schema": "orbit.prediction.v1",
                "ra_deg": "123.456789",
            }),
        },
        {
            "name": "32-byte CosmWasm contract address (code 1, instance 1), non-ASCII payload",
            "creator_raw": contract,
            "salt": hashlib.sha256(b"medas-notary test vector 2").digest(),
            "payload": canonical_json({
                "note": "Δt ≤ 0.5 s, Beobachter: Sternwarte Göttingen",
                "object": "(3200) Phaethon",
                "observer": "Müller",
            }),
        },
        {
            "name": "minimal payload (1 byte), salt of 0xff",
            "creator_raw": bytes([1] * 20),
            "salt": b"\xff" * 32,
            "payload": b"x",
        },
        {
            "name": "binary payload with NUL and invalid UTF-8 (chain does not interpret the payload)",
            "creator_raw": gov,
            "salt": bytes(range(32)),
            "payload": b"\x00\xff\xfe\x00",
        },
    ]
    vectors = []
    for c in cases:
        creator = bech32_encode(HRP, c["creator_raw"])
        digest = content_sha256(c["payload"])
        pre = preimage(c["creator_raw"], c["salt"], digest)
        vectors.append({
            "name": c["name"],
            "creator": creator,
            "creator_hex": c["creator_raw"].hex(),
            "salt_hex": c["salt"].hex(),
            "payload_hex": c["payload"].hex(),
            "content_sha256_hex": digest.hex(),
            "payload_utf8": c["payload"].decode("utf-8") if _is_utf8(c["payload"]) else None,
            "preimage_hex": pre.hex(),
            "hash_hex": hashlib.sha256(pre).hexdigest(),
        })

    # Negative cases: the listed inputs must NOT reproduce the given hash.
    v0 = vectors[0]
    negatives = [
        {
            "name": "same salt and payload, different creator (copied hash)",
            "creator": bech32_encode(HRP, bytes([1] * 20)),
            "salt_hex": v0["salt_hex"],
            "payload_hex": v0["payload_hex"],
            "hash_hex": v0["hash_hex"],
        },
        {
            "name": "payload with trailing newline",
            "creator": v0["creator"],
            "salt_hex": v0["salt_hex"],
            "payload_hex": v0["payload_hex"] + "0a",
            "hash_hex": v0["hash_hex"],
        },
        {
            "name": "salt with last byte changed",
            "creator": v0["creator"],
            "salt_hex": v0["salt_hex"][:-2] + "20",
            "payload_hex": v0["payload_hex"],
            "hash_hex": v0["hash_hex"],
        },
    ]
    return {
        "description": "medas notary commitment hash test vectors, protocol v1 (docs/notary-spec.md). "
                       "Generated by scripts/notary_hash.py make-vectors.",
        "domain": DOMAIN.decode(),
        "hrp": HRP,
        "vectors": vectors,
        "negative": negatives,
    }


def _is_utf8(b):
    try:
        b.decode("utf-8")
        return True
    except UnicodeDecodeError:
        return False


def verify_vectors(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    ok = True
    for v in data["vectors"]:
        salt, payload = bytes.fromhex(v["salt_hex"]), bytes.fromhex(v["payload_hex"])
        raw = address_bytes(v["creator"], data["hrp"])
        digest = content_sha256(payload)
        checks = {
            "creator_hex": raw.hex() == v["creator_hex"],
            "payload_utf8": v["payload_utf8"] is None or v["payload_utf8"].encode("utf-8") == payload,
            "content_sha256": digest.hex() == v["content_sha256_hex"],
            "preimage": preimage(raw, salt, digest).hex() == v["preimage_hex"],
            "hash_from_digest": commitment_hash_from_digest(v["creator"], salt, digest, data["hrp"]).hex() == v["hash_hex"],
            "hash": commitment_hash(v["creator"], salt, payload, data["hrp"]).hex() == v["hash_hex"],
        }
        good = all(checks.values())
        ok &= good
        print(("ok  " if good else "FAIL"), v["name"], "" if good else checks)
    for v in data.get("negative", []):
        h = commitment_hash(v["creator"], bytes.fromhex(v["salt_hex"]), bytes.fromhex(v["payload_hex"]), data["hrp"])
        good = h.hex() != v["hash_hex"]
        ok &= good
        print(("ok  " if good else "FAIL"), "negative:", v["name"])
    return ok


# --------------------------------------------------------------------------


def _read_payload(a):
    if a.payload is not None:
        return a.payload.encode("utf-8")
    if a.payload_file is not None:
        with open(a.payload_file, "rb") as f:
            return f.read()
    return bytes.fromhex(a.payload_hex)


def main(argv):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("salt")
    h = sub.add_parser("hash")
    h.add_argument("--creator", required=True)
    h.add_argument("--salt", required=True, help="32 bytes hex")
    g = h.add_mutually_exclusive_group(required=True)
    g.add_argument("--payload", help="UTF-8 string (used as is, not canonicalised)")
    g.add_argument("--payload-file")
    g.add_argument("--payload-hex")
    g.add_argument("--content-sha256", help="SHA-256 of the content, 32 bytes hex")
    h.add_argument("--hrp", default=HRP)
    d = sub.add_parser("content-sha256")
    gd = d.add_mutually_exclusive_group(required=True)
    gd.add_argument("--payload")
    gd.add_argument("--payload-file")
    gd.add_argument("--payload-hex")
    c = sub.add_parser("canonical-json")
    c.add_argument("file")
    v = sub.add_parser("vectors")
    v.add_argument("file", nargs="?", default=DEFAULT_VECTORS)
    sub.add_parser("make-vectors")
    a = p.parse_args(argv)

    if a.cmd == "salt":
        print(secrets.token_bytes(SALT_LEN).hex())
    elif a.cmd == "hash":
        if a.content_sha256 is not None:
            digest = bytes.fromhex(a.content_sha256)
        else:
            digest = content_sha256(_read_payload(a))
        print(commitment_hash_from_digest(a.creator, bytes.fromhex(a.salt), digest, a.hrp).hex())
    elif a.cmd == "content-sha256":
        print(content_sha256(_read_payload(a)).hex())
    elif a.cmd == "canonical-json":
        with open(a.file, encoding="utf-8") as f:
            sys.stdout.buffer.write(canonical_json(json.load(f)))
    elif a.cmd == "vectors":
        return 0 if verify_vectors(a.file) else 1
    elif a.cmd == "make-vectors":
        print(json.dumps(make_vectors(), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
