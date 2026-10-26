import collections
import importlib.util
import json
from pathlib import Path
import unittest

BASE = Path(__file__).parent
class CorpusTests(unittest.TestCase):
    def setUp(self):
        self.rows = json.loads((BASE / 'corpus-200.json').read_text())
    def test_balanced_independent_inputs(self):
        self.assertEqual(collections.Counter(r['category'] for r in self.rows),
                         dict(chinese=50, english=50, protected=50, correct=50))
        self.assertEqual(len({r['id'] for r in self.rows}), 200)
        self.assertEqual(len({r['text'] for r in self.rows}), 200)
    def test_limits_and_labels(self):
        for row in self.rows:
            self.assertLessEqual(len(row['text']), 256)
            self.assertLessEqual(len(row['text'].encode()), 1024)
            self.assertEqual(row['isEnglish'], row['text'].isascii())
            self.assertTrue(row['expected'])
            self.assertEqual(row['text'] in row['expected'], row['category'] in ('protected', 'correct'))
    def test_reproducible_without_writing_files(self):
        spec = importlib.util.spec_from_file_location('assist_corpus', BASE / 'make_corpus.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(module.build(), self.rows)
    def test_prediction_examples_are_separate(self):
        rows = json.loads((BASE / 'prediction-20.json').read_text())
        self.assertEqual(len(rows), 20)
        self.assertEqual(len({r['text'] for r in rows}), 20)
        self.assertTrue(all(r['category'] == 'prediction' and r['isEnglish'] for r in rows))
        self.assertFalse({r['text'] for r in rows} & {r['text'] for r in self.rows})
if __name__ == '__main__':
    unittest.main()
