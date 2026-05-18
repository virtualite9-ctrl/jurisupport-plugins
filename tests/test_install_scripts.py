import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class InstallScriptTests(unittest.TestCase):
    def test_toolkit_installers_avoid_python_314_for_pydantic_pins(self):
        for rel in [
            "toolkit/legal-books/install.sh",
            "toolkit/case-records/install.sh",
        ]:
            with self.subTest(rel=rel):
                script = (ROOT / rel).read_text()
                self.assertIn("select_python()", script)
                self.assertRegex(script, r"minor.*-le 13")
                self.assertIn('"$PYTHON_BIN" -m venv', script)

    def test_gemini_dependency_removed_from_local_embedding_toolkits(self):
        for rel in [
            "toolkit/legal-books/install.sh",
            "toolkit/case-records/install.sh",
            "toolkit/legal-books/scripts/ingest.py",
            "toolkit/case-records/scripts/ingest_case.py",
        ]:
            with self.subTest(rel=rel):
                text = (ROOT / rel).read_text()
                self.assertNotRegex(text, re.compile(r"google-genai|GEMINI_API_KEY|text-embedding-004"))


if __name__ == "__main__":
    unittest.main()
