#!/usr/bin/env python3
"""Extract readable text from a document and split it into TTS-sized chunks."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# These abbreviations should not normally terminate a sentence.
ABBREVIATIONS = {
    'mr.', 'mrs.', 'ms.', 'dr.', 'prof.', 'sr.', 'jr.', 'st.', 'vs.',
    'etc.', 'e.g.', 'i.e.', 'fig.', 'no.', 'inc.', 'a.m.', 'p.m.',
    'jen.', 'professor.',
}


def normalize_text(text: str) -> str:
    """Join wrapped lines while preserving paragraph boundaries.

    PDF layout extraction is imperfect; this intentionally does not remove
    hyphens because a line-final hyphen may be part of a genuine compound.
    """
    text = text.replace('\r\n', '\n').replace('\r', '\n').replace('\f', '\n\n')
    paragraphs = re.split(r'\n\s*\n+', text)
    return '\n\n'.join(
        cleaned for p in paragraphs
        if (cleaned := re.sub(r'\s+', ' ', p).strip())
    )


def split_sentences(paragraph: str) -> list[str]:
    """Split at sentence punctuation, preserving common abbreviations/decimals."""
    sentences = []
    start = 0
    for match in re.finditer(r'[.!?…]+["\'’”»\)\]]*(?=\s|$)', paragraph):
        end = match.end()
        punctuation = match.group(0)
        if punctuation.startswith('.'):
            before = paragraph[start:match.start() + 1]
            word = re.search(r'(?:[\w]\.){2,}$|[\w]+\.$', before, re.UNICODE)
            token = word.group(0).lower() if word else ''
            if token in ABBREVIATIONS or re.fullmatch(r'(?:[a-zA-Z]\.){2,}', token):
                continue
            # A single initial (e.g. A. Smith) is usually not a sentence.
            if re.fullmatch(r'[A-Z]\.', token) and paragraph[end:].strip():
                continue
        sentence = paragraph[start:end].strip()
        if sentence:
            sentences.append(sentence)
        start = end
    tail = paragraph[start:].strip()
    if tail:
        sentences.append(tail)
    return sentences


def split_long_text(text: str, limit: int) -> list[str]:
    """Split oversized sentences at words, hard-splitting only oversized tokens."""
    parts, current = [], ''
    for word in text.split():
        while len(word) > limit:
            if current:
                parts.append(current)
                current = ''
            parts.append(word[:limit])
            word = word[limit:]
        if not word:
            continue
        if current and len(current) + 1 + len(word) > limit:
            parts.append(current)
            current = ''
        current = f'{current} {word}' if current else word
    if current:
        parts.append(current)
    return parts


def make_chunks(text: str, max_chars: int = 500, dedupe: bool = False) -> list[str]:
    """Group complete sentences up to max_chars, preferring paragraph breaks."""
    if max_chars < 1:
        raise ValueError('max_chars must be at least 1')
    chunks = []
    seen: set[str] = set()
    for paragraph in normalize_text(text).split('\n\n'):
        current = ''
        for sentence in split_sentences(paragraph):
            if dedupe:
                key = sentence.casefold()
                if key in seen:
                    continue
                seen.add(key)
            for part in split_long_text(sentence, max_chars):
                if current and len(current) + 1 + len(part) > max_chars:
                    chunks.append(current)
                    current = ''
                current = f'{current} {part}' if current else part
        if current:
            chunks.append(current)
    return chunks



def categorize_chunks(text: str, categories: dict[str, list[str]], max_chars: int,
                      dedupe: bool = False) -> dict[str, list[str]]:
    """Assign sentences to every keyword-matching category, preserving order."""
    groups: dict[str, list[str]] = {name: [] for name in categories}
    groups['uncategorized'] = []
    seen: set[str] = set()
    for paragraph in normalize_text(text).split('\n\n'):
        for sentence in split_sentences(paragraph):
            key = sentence.casefold()
            if dedupe and key in seen:
                continue
            seen.add(key)
            matches = [name for name, words in categories.items()
                       if any(re.search(r'(?<!\w)' + re.escape(word.casefold()) + r'(?!\w)', key)
                              for word in words)]
            for name in matches or ['uncategorized']:
                groups[name].append(sentence)
    return {name: make_chunks(' '.join(sentences), max_chars)
            for name, sentences in groups.items() if sentences}


def load_categories(path: Path) -> dict[str, list[str]]:
    data = json.loads(path.read_text(encoding='utf-8-sig'))
    if not isinstance(data, dict) or not data:
        raise ValueError('Kategoriýa JSON faýly boş däl obýekt bolmaly.')
    for name, words in data.items():
        if (not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9_-]+', name)
                or name.lower() == 'uncategorized'):
            raise ValueError('Kategoriýa ady diňe latyn harplary, san, _ ýa-da - bolup biler; uncategorized aýratyn adydyr.')
        if (not isinstance(words, list) or not words
                or any(not isinstance(w, str) or not w.strip() or w != w.strip() for w in words)):
            raise ValueError('Her kategoriýa boş däl açar sözler sanawy bolmaly.')
    if len({name.lower() for name in data}) != len(data):
        raise ValueError('Kategoriýa atlary uly-kiçi harpa seretmezden tapawutly bolmaly.')
    return data

def extract_text(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == '.txt':
        return path.read_text(encoding='utf-8-sig')
    if suffix == '.pdf':
        try:
            import pymupdf
        except ImportError as exc:
            raise RuntimeError('PDF üçin PyMuPDF guruň: pip install PyMuPDF') from exc
        with pymupdf.open(path) as document:
            if document.is_encrypted:
                raise ValueError('Şifrlenen PDF goldanylmaýar.')
            return '\n\n'.join(page.get_text('text', sort=True) for page in document)
    if suffix == '.docx':
        try:
            from docx import Document
        except ImportError as exc:
            raise RuntimeError('DOCX üçin python-docx guruň: pip install python-docx') from exc
        # iter_inner_content preserves body paragraph/table order (python-docx >= 1.1).
        from docx.table import Table
        from docx.text.paragraph import Paragraph
        pieces = []
        for block in Document(path).iter_inner_content():
            if isinstance(block, Paragraph):
                pieces.append(block.text)
            elif isinstance(block, Table):
                for row in block.rows:
                    pieces.append(' | '.join(cell.text for cell in row.cells))
        return '\n\n'.join(pieces)
    raise ValueError('Diňe .pdf, .docx we .txt goldanylýar. .doc faýlyny ilki .docx ediň.')


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description='PDF, DOCX ýa-da TXT faýlyny TTS üçin böleklere bölüň.')
    parser.add_argument('input', type=Path, help='Giriş faýly (.pdf, .docx, .txt)')
    destination = parser.add_mutually_exclusive_group(required=True)
    destination.add_argument('-o', '--output', type=Path, help='Çykyş faýly (.json ýa-da .txt)')
    destination.add_argument('--output-dir', type=Path, help='Her bölegi aýratyn belgili TXT faýly hökmünde sakla')
    parser.add_argument('--categories', type=Path, help='Tema açar sözleri ýazylan JSON faýly (diňe --output-dir bilen)')
    parser.add_argument('--dedupe', action='store_true', help='Gaýtalanýan doly sözlemleri aýyr (başlangyçda saklanýar)')
    parser.add_argument('--max-chars', type=int, default=500, help='Her bölegiň iň köp simwol sany (başlangyç: 500)')
    args = parser.parse_args(argv)
    if args.categories and not args.output_dir:
        parser.error('--categories üçin --output-dir gerek')
    if args.max_chars < 1:
        parser.error('--max-chars azyndan 1 bolmaly')
    if args.output and args.output.suffix.lower() not in {'.json', '.txt'}:
        parser.error('Çykyş faýly .json ýa-da .txt bolmaly')
    if args.output and args.input.resolve() == args.output.resolve():
        parser.error('Giriş we çykyş faýllary bir bolmaly däl')
    try:
        text = extract_text(args.input)
        categories = load_categories(args.categories) if args.categories else None
        groups = categorize_chunks(text, categories, args.max_chars, args.dedupe) if categories else None
        chunks = make_chunks(text, args.max_chars, args.dedupe) if groups is None else []
        if not chunks and not groups:
            raise ValueError('Tekst tapylmady. Skanirlenen PDF bolsa, ilki OCR ulanyň.')
        if args.output_dir:
            args.output_dir.mkdir(parents=True, exist_ok=True)
            # Refuse an existing destination rather than overwrite files or leave
            # stale numbered chunks from an earlier, longer run.
            if any(args.output_dir.iterdir()):
                raise ValueError('Çykyş bukjasy boş bolmaly.')
            destinations = groups if groups is not None else {'': chunks}
            for name, items in destinations.items():
                directory = args.output_dir / name if name else args.output_dir
                directory.mkdir(parents=True, exist_ok=True)
                width = max(6, len(str(len(items))))
                for number, chunk in enumerate(items, 1):
                    (directory / f'chunk_{number:0{width}d}.txt').write_text(chunk, encoding='utf-8')
        else:
            content = (json.dumps(chunks, ensure_ascii=False, indent=2) + '\n'
                       if args.output.suffix.lower() == '.json' else '\n\n'.join(chunks) + '\n')
            args.output.write_text(content, encoding='utf-8')
    except (OSError, ValueError, RuntimeError) as exc:
        print(f'Ýalňyşlyk: {exc}', file=sys.stderr)
        return 1
    total = sum(map(len, groups.values())) if groups is not None else len(chunks)
    print(f'{total} bölek taýýar: {args.output_dir or args.output}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
