import json
import tempfile
import unittest
from pathlib import Path

from tts_chunks import main, make_chunks, normalize_text, split_sentences, categorize_chunks, load_categories


class ChunkTests(unittest.TestCase):
    def test_sentences_and_abbreviations(self):
        self.assertEqual(split_sentences('Dr. Smith geldi. Näme? Hawa!'),
                         ['Dr. Smith geldi.', 'Näme?', 'Hawa!'])

    def test_normalization_and_paragraphs(self):
        self.assertEqual(normalize_text('Bir\nsetir.\n\nIkinji\nsetir.'),
                         'Bir setir.\n\nIkinji setir.')
        self.assertEqual(make_chunks('Bir.\n\nIki.', 100), ['Bir.', 'Iki.'])

    def test_long_sentence_and_token(self):
        chunks = make_chunks('bir iki abcdefghijkl soň.', 5)
        self.assertTrue(all(len(x) <= 5 for x in chunks))
        self.assertEqual(chunks, ['bir', 'iki', 'abcde', 'fghij', 'kl', 'soň.'])

    def test_empty_and_invalid_limit(self):
        self.assertEqual(make_chunks(' \n\n ', 10), [])
        with self.assertRaises(ValueError):
            make_chunks('text', 0)

    def test_dedupe_is_opt_in(self):
        text = 'Salam dünýä! Hawa.\n\nSALAM DÜNÝÄ! Hawa.'
        self.assertEqual(make_chunks(text, 100), ['Salam dünýä! Hawa.', 'SALAM DÜNÝÄ! Hawa.'])
        self.assertEqual(make_chunks(text, 100, dedupe=True), ['Salam dünýä! Hawa.'])

    def test_output_dir_numbered_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as d:
            source = Path(d) / 'in.txt'
            output = Path(d) / 'chunks'
            source.write_text('Birinji. Ikinji. Üçünji.', encoding='utf-8')
            self.assertEqual(main([str(source), '--output-dir', str(output), '--max-chars', '10']), 0)
            files = sorted(output.glob('*.txt'))
            self.assertEqual([p.name for p in files], ['chunk_000001.txt', 'chunk_000002.txt', 'chunk_000003.txt'])
            self.assertEqual([p.read_text(encoding='utf-8') for p in files], ['Birinji.', 'Ikinji.', 'Üçünji.'])
            self.assertEqual(main([str(source), '--output-dir', str(output)]), 1)

    def test_categories_overlap_and_unmatched(self):
        groups = categorize_chunks('Ylym we saglyk. Başga zat. Ylym we saglyk.',
                                   {'ylym': ['ylym'], 'saglyk': ['saglyk']}, 100, True)
        self.assertEqual(groups, {'ylym': ['Ylym we saglyk.'], 'saglyk': ['Ylym we saglyk.'], 'uncategorized': ['Başga zat.']})
        self.assertEqual(categorize_chunks('Ylymly adam.', {'ylym': ['ylym']}, 100),
                         {'uncategorized': ['Ylymly adam.']})

    def test_category_cli_and_validation(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            source, config, output = root / 'in.txt', root / 'c.json', root / 'out'
            source.write_text('Ylym bar. Näbelli.', encoding='utf-8')
            config.write_text(json.dumps({'ylym': ['ylym']}), encoding='utf-8')
            self.assertEqual(main([str(source), '--output-dir', str(output), '--categories', str(config)]), 0)
            self.assertEqual((output / 'ylym' / 'chunk_000001.txt').read_text(encoding='utf-8'), 'Ylym bar.')
            self.assertEqual((output / 'uncategorized' / 'chunk_000001.txt').read_text(encoding='utf-8'), 'Näbelli.')
            config.write_text(json.dumps({'../bad': ['x']}), encoding='utf-8')
            with self.assertRaises(ValueError):
                load_categories(config)

    def test_cli_json_unicode(self):
        with tempfile.TemporaryDirectory() as d:
            source = Path(d) / 'in.txt'
            output = Path(d) / 'out.json'
            source.write_text('Salam dünýä! Nähili?', encoding='utf-8')
            self.assertEqual(main([str(source), '-o', str(output), '--max-chars', '15']), 0)
            self.assertEqual(json.loads(output.read_text(encoding='utf-8')),
                             ['Salam dünýä!', 'Nähili?'])


if __name__ == '__main__':
    unittest.main()
