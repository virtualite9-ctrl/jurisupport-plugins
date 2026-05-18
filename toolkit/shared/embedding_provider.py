#!/usr/bin/env python3
"""Local embedding provider for jurisupport toolkits.

Default mode is OpenAI-compatible `/v1/embeddings` so Gemini is not required.
Set these in ~/.jurisupport/secrets.env or the process environment:

  JURISUPPORT_EMBEDDING_PROVIDER=openai   # openai | hash
  JURISUPPORT_EMBEDDING_BASE_URL=http://127.0.0.1:3333/v1
  JURISUPPORT_EMBEDDING_MODEL=<local embedding model id>
  JURISUPPORT_EMBEDDING_API_KEY=no-key-required

`hash` is an offline deterministic fallback for smoke tests and air-gapped
setups. It is not semantically as strong as a real embedding model.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
import urllib.error
import urllib.request
from typing import Iterable

DEFAULT_EMBEDDING_DIM = 768
DEFAULT_BASE_URL = "http://127.0.0.1:3333/v1"
DEFAULT_API_KEY = "no-key-required"
DEFAULT_MODEL = "local-embedding"

_TOKEN_RE = re.compile(r"[0-9A-Za-z가-힣]+")


class EmbeddingProviderError(RuntimeError):
    """Raised when embeddings cannot be generated."""


def _env(name: str, default: str) -> str:
    return (os.environ.get(name) or default).strip()


def _hash_embedding(text: str, dim: int = DEFAULT_EMBEDDING_DIM) -> list[float]:
    """Deterministic local lexical embedding.

    This is deliberately simple and dependency-free. It gives useful lexical
    recall when a local OpenAI-compatible endpoint does not expose embeddings,
    but semantic quality depends on using a real embedding endpoint.
    """
    vec = [0.0] * dim
    tokens = _TOKEN_RE.findall(text.lower())
    # Include short character n-grams so Korean text without spaces still works.
    compact = re.sub(r"\s+", "", text.lower())
    grams = [compact[i : i + 3] for i in range(max(0, len(compact) - 2))]
    features = tokens + grams
    if not features:
        return vec
    for feature in features:
        digest = hashlib.sha256(feature.encode("utf-8")).digest()
        idx = int.from_bytes(digest[:4], "big") % dim
        sign = 1.0 if digest[4] % 2 == 0 else -1.0
        vec[idx] += sign
    norm = math.sqrt(sum(v * v for v in vec))
    if norm:
        vec = [v / norm for v in vec]
    return vec


def _openai_embeddings(texts: list[str]) -> list[list[float]]:
    base_url = _env("JURISUPPORT_EMBEDDING_BASE_URL", DEFAULT_BASE_URL).rstrip("/")
    model = _env("JURISUPPORT_EMBEDDING_MODEL", DEFAULT_MODEL)
    api_key = _env("JURISUPPORT_EMBEDDING_API_KEY", DEFAULT_API_KEY)
    timeout = float(_env("JURISUPPORT_EMBEDDING_TIMEOUT", "120"))

    payload = json.dumps({"model": model, "input": texts}).encode("utf-8")
    request = urllib.request.Request(
        f"{base_url}/embeddings",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:1000]
        raise EmbeddingProviderError(
            f"OpenAI-compatible embedding endpoint failed: HTTP {exc.code}: {detail}"
        ) from exc
    except Exception as exc:  # noqa: BLE001 - CLI/server should surface readable error
        raise EmbeddingProviderError(
            f"OpenAI-compatible embedding endpoint failed at {base_url}/embeddings: {exc}"
        ) from exc

    try:
        parsed = json.loads(body)
        data = parsed["data"]
        data = sorted(data, key=lambda item: item.get("index", 0))
        vectors = [item["embedding"] for item in data]
    except Exception as exc:  # noqa: BLE001
        raise EmbeddingProviderError(f"Invalid embeddings response: {body[:1000]}") from exc

    if len(vectors) != len(texts):
        raise EmbeddingProviderError(
            f"Embedding count mismatch: expected {len(texts)}, got {len(vectors)}"
        )
    return vectors


def embed_texts(texts: Iterable[str]) -> list[list[float]]:
    items = list(texts)
    provider = _env("JURISUPPORT_EMBEDDING_PROVIDER", "openai").lower()
    if provider in {"hash", "local-hash", "offline"}:
        dim = int(_env("JURISUPPORT_EMBEDDING_DIM", str(DEFAULT_EMBEDDING_DIM)))
        return [_hash_embedding(text, dim=dim) for text in items]
    if provider in {"openai", "openai-compatible", "local-llm"}:
        try:
            return _openai_embeddings(items)
        except EmbeddingProviderError:
            fallback = _env("JURISUPPORT_EMBEDDING_FALLBACK", "hash").lower()
            if fallback in {"hash", "local-hash", "offline"}:
                dim = int(_env("JURISUPPORT_EMBEDDING_DIM", str(DEFAULT_EMBEDDING_DIM)))
                return [_hash_embedding(text, dim=dim) for text in items]
            raise
    raise EmbeddingProviderError(
        "Unsupported JURISUPPORT_EMBEDDING_PROVIDER "
        f"'{provider}'. Use 'openai' or 'hash'."
    )


def embed_text(text: str) -> list[float]:
    return embed_texts([text])[0]
