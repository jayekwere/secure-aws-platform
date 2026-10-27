"""Reject mutable action references and unexpected workflow write permissions."""
from pathlib import Path
import re

for path in Path('.github/workflows').glob('*.yml'):
    text = path.read_text()
    refs = re.findall(r'uses:\s*([^\s#]+)', text)
    assert refs and all(re.fullmatch(r'[\w.-]+/[\w./-]+@[0-9a-f]{40}', ref) for ref in refs), (path, refs)
    assert not re.search(r'\b(?:contents|id-token|actions|pull-requests):\s*write', text), path
print('PASS immutable action references; no deployment or repository-write permission')
