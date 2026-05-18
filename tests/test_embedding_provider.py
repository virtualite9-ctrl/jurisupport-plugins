import importlib.util
import json
import os
import pathlib
import sys
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]
PROVIDER_PATH = ROOT / "toolkit" / "shared" / "embedding_provider.py"


def load_provider():
    spec = importlib.util.spec_from_file_location("embedding_provider", PROVIDER_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules["embedding_provider"] = module
    spec.loader.exec_module(module)
    return module


class EmbeddingProviderTests(unittest.TestCase):
    def test_hash_provider_is_local_deterministic_and_dimensioned(self):
        provider = load_provider()
        with mock.patch.dict(os.environ, {"JURISUPPORT_EMBEDDING_PROVIDER": "hash"}, clear=False):
            first = provider.embed_texts(["민법상 소멸시효", "채무승인"])
            second = provider.embed_texts(["민법상 소멸시효", "채무승인"])

        self.assertEqual(first, second)
        self.assertEqual(len(first), 2)
        self.assertEqual(len(first[0]), provider.DEFAULT_EMBEDDING_DIM)
        self.assertTrue(any(v != 0 for v in first[0]))

    def test_openai_compatible_provider_posts_to_local_embeddings_endpoint(self):
        provider = load_provider()
        captured = {}

        class FakeResponse:
            def __enter__(self):
                return self
            def __exit__(self, exc_type, exc, tb):
                return False
            def read(self):
                return json.dumps({
                    "data": [
                        {"index": 1, "embedding": [0.0, 1.0]},
                        {"index": 0, "embedding": [1.0, 0.0]},
                    ]
                }).encode()

        def fake_urlopen(req, timeout):
            captured["url"] = req.full_url
            captured["timeout"] = timeout
            captured["headers"] = dict(req.header_items())
            captured["payload"] = json.loads(req.data.decode())
            return FakeResponse()

        env = {
            "JURISUPPORT_EMBEDDING_PROVIDER": "openai",
            "JURISUPPORT_EMBEDDING_BASE_URL": "http://127.0.0.1:3333/v1",
            "JURISUPPORT_EMBEDDING_MODEL": "local-embedding-model",
            "JURISUPPORT_EMBEDDING_API_KEY": "no-key-required",
        }
        with mock.patch.dict(os.environ, env, clear=False), mock.patch("urllib.request.urlopen", fake_urlopen):
            vectors = provider.embed_texts(["첫번째", "두번째"])

        self.assertEqual(captured["url"], "http://127.0.0.1:3333/v1/embeddings")
        self.assertEqual(captured["payload"], {"model": "local-embedding-model", "input": ["첫번째", "두번째"]})
        self.assertEqual(vectors, [[1.0, 0.0], [0.0, 1.0]])


if __name__ == "__main__":
    unittest.main()
