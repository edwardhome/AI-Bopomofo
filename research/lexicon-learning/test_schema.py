"""只使用公開合成資料驗證交換格式；不讀取本機學習資料庫。"""
import copy
import hashlib
import json
import pathlib
import struct
import unittest
from jsonschema import Draft202012Validator, ValidationError

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCHEMA = json.loads((ROOT / "schemas/lexicon-v1.schema.json").read_text())
EXAMPLE = json.loads((ROOT / "examples/lexicon-review-example.json").read_text())


class SchemaContractTests(unittest.TestCase):
    def test_schema_and_example(self):
        Draft202012Validator.check_schema(SCHEMA)
        Draft202012Validator(SCHEMA).validate(EXAMPLE)

    def test_identity_matches_documented_bytes(self):
        for entry in EXAMPLE["entries"]:
            values = [entry["term_type"], entry["reading"], entry["text"]]
            encoded = b"".join(struct.pack(">Q", len(v.encode())) + v.encode() for v in values)
            self.assertEqual(hashlib.sha256(encoded).hexdigest(), entry["entry_id"])

    def test_unsupported_version(self):
        value = copy.deepcopy(EXAMPLE)
        value["schema_version"] = "2.0.0"
        with self.assertRaises(ValidationError):
            Draft202012Validator(SCHEMA).validate(value)

    def test_unknown_fields_and_prefer_rejected(self):
        for key, value in [("policy", "prefer"), ("execute", "anything")]:
            document = copy.deepcopy(EXAMPLE)
            document["entries"][0][key] = value
            with self.assertRaises(ValidationError):
                Draft202012Validator(SCHEMA).validate(document)

    def test_technical_codes_and_controls(self):
        for key, value in [("reading", "a b"), ("text", "Si\x00O2")]:
            document = copy.deepcopy(EXAMPLE)
            document["entries"][1][key] = value
            with self.assertRaises(ValidationError):
                Draft202012Validator(SCHEMA).validate(document)


if __name__ == "__main__":
    unittest.main()
