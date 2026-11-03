# Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
"""無介面檢查：97 列審核涵蓋率、詞條與字元資料，完全不讀私人原報告。"""
import json
import pathlib
import re
import unicodedata
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG_PATH = ROOT / 'Packages/MixedInputCore/Sources/MixedInputCore/Resources/engineering-terms.json'
CATALOG = json.loads(CATALOG_PATH.read_text())
REVIEW = json.loads((ROOT / 'docs/science-terms-review.json').read_text())


class CatalogTests(unittest.TestCase):
    def test_all_97_source_rows_have_a_review_and_resolved_entries(self):
        expected = {f'{table}.{row}' for table, count in enumerate((13, 11, 14, 13, 46), 1)
                    for row in range(1, count + 1)}
        self.assertEqual({r['row'] for r in REVIEW['rows']}, expected)
        self.assertEqual(len(REVIEW['rows']), 97)
        ids = [t['id'] for t in CATALOG['terms']]
        reviewed = [i for r in REVIEW['rows'] for i in r['termIDs']]
        self.assertEqual(sorted(ids), sorted(reviewed))
        self.assertEqual(len(ids), len(set(ids)))
        for row in REVIEW['rows']:
            self.assertIn(row['status'], ('收錄', '修正', '暫緩'))
            self.assertTrue(row['reason'])
        self.assertRegex(REVIEW['sourceSHA256'], r'^[0-9a-f]{64}$')

    def test_outputs_are_safe_text_with_unicode_before_ascii(self):
        for term in CATALOG['terms']:
            seen_ascii = False
            self.assertEqual(len(term['outputs']), len(set(term['outputs'])))
            for output in term['outputs']:
                self.assertTrue(output)
                self.assertLessEqual(len(output.encode('utf-16-le')) // 2, 128)
                for char in output:
                    self.assertNotIn(unicodedata.category(char), ('Cc', 'Cf', 'Cs', 'Co', 'Cn'))
                    self.assertNotIn(char, '\n\r')
                if output.isascii():
                    seen_ascii = True
                else:
                    self.assertFalse(seen_ascii, term['id'])
                self.assertNotIn('\\text', output)
                self.assertNotIn('$', output)

    def test_sources_and_aliases_are_traceable_without_private_export(self):
        text = CATALOG_PATH.read_text()
        for forbidden in ('gemini.google.com', 'exportedAt', '<html', '/Users/', '/Volumes/'):
            self.assertNotIn(forbidden, text)
        for term in CATALOG['terms']:
            self.assertTrue(term['annotation'])
            self.assertTrue(term['category'])
            self.assertTrue(term['sources'][0].startswith('report-row:'))
            for source in term['sources'][1:]:
                self.assertTrue(source.startswith('https://'))
            for alias in term['aliases']:
                self.assertTrue(2 <= len(alias) <= 64)
                self.assertRegex(alias, r'^[!-~]+$')

    def test_known_report_errors_do_not_enter_candidates(self):
        by_id = {t['id']: t for t in CATALOG['terms']}
        self.assertEqual(by_id['4.1.1']['outputs'][0], 'ℏ')
        self.assertEqual(unicodedata.name('ℏ'), 'PLANCK CONSTANT OVER TWO PI')
        self.assertEqual(unicodedata.name(chr(0x2097)), 'LATIN SUBSCRIPT SMALL LETTER L')
        self.assertEqual(by_id['4.3.1']['outputs'], ['k_B', 'kB'])
        self.assertEqual(by_id['4.9.1']['outputs'][0], '°C')
        self.assertEqual(by_id['5.33.1']['outputs'], ['YBCO'])
        self.assertEqual(by_id['5.43.1']['outputs'][0], 'H⁺')
        self.assertEqual(by_id['5.43.2']['outputs'][0], 'H₃O⁺')
        self.assertEqual(by_id['5.44.1']['outputs'], ['SO₄²⁻', 'SO4^2-'])

    def test_documented_terms_and_reference_keys_are_complete(self):
        doc = (ROOT / 'docs/science-terms-catalog.md').read_text()
        for term in CATALOG['terms']:
            for output in term['outputs']:
                self.assertIn(f'`{output}`', doc)
        for row in REVIEW['rows']:
            self.assertTrue(set(row['sourceKeys']).issubset(REVIEW['sources']))
        self.assertEqual(CATALOG['version'], 1)
        self.assertLess(CATALOG_PATH.stat().st_size, 1024 * 1024)


if __name__ == '__main__':
    unittest.main()
