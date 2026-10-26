#!/usr/bin/env python3
"""Install local editor hooks after building the helper and registering AI-Bopomofo 0.6.0."""
from pathlib import Path
from datetime import datetime
import json, re, shutil, subprocess

repo = Path(__file__).resolve().parents[2]
built = repo / 'build/vim/ai-bopomofo-input'
normal = subprocess.check_output([str(built), '--normal-source'], text=True).strip()
helper = Path.home() / '.local/bin/ai-bopomofo-input'
settings = Path.home() / 'Library/Application Support/Code/User/settings.json'
values = {
    'vim.autoSwitchInputMethod.enable': True,
    'vim.autoSwitchInputMethod.defaultIM': normal,
    'vim.autoSwitchInputMethod.obtainIMCmd': str(helper) + ' --vscode-obtain',
    'vim.autoSwitchInputMethod.switchIMCmd': str(helper) + ' {im}',
}
original = settings.read_bytes() if settings.exists() else b'{}\n'
text = original.decode('utf-8-sig')
assert text.lstrip().startswith('{'), 'Expected a JSONC settings object'
newline = '\r\n' if b'\r\n' in original else '\n'
missing = {}
for key, value in values.items():
    # Preserve existing JSONC comments and unrelated preferences. Reject ambiguous formatting.
    pattern = r'(?m)^(\s*)' + re.escape(json.dumps(key)) + r'\s*:\s*(?:"(?:\\.|[^"\\])*"|true|false)(?=\s*[,}])'
    matches = list(re.finditer(pattern, text))
    if matches:
        assert len(matches) == 1, 'Duplicate setting: ' + key
        text = re.sub(pattern, lambda m: m.group(1) + json.dumps(key) + ': ' + json.dumps(value), text)
    else:
        assert json.dumps(key) not in text, 'Please normalize setting formatting: ' + key
        missing[key] = value
if missing:
    pos = text.index('{') + 1
    content = newline + ''.join('    '+json.dumps(k)+': '+json.dumps(v)+','+newline for k,v in missing.items())
    if text[pos:].lstrip().startswith('}'):
        content = content.rstrip(newline).removesuffix(',') + newline
    text = text[:pos] + content + text[pos:]
backup = repo / 'artifacts/install-vim' / datetime.now().astimezone().strftime('%Y%m%dT%H%M%S%z')
backup.mkdir(parents=True, exist_ok=False)
(backup/'vscode-settings-before.json').write_bytes(original)
for label, source, target in [
    ('helper', built, helper),
    ('vim-plugin', repo/'integrations/vim/ai-bopomofo.vim', Path.home()/'.vim/plugin/ai-bopomofo.vim'),
    ('nvim-plugin', repo/'integrations/vim/ai-bopomofo.vim', Path.home()/'.config/nvim/plugin/ai-bopomofo.vim'),
]:
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists(): shutil.copy2(target, backup/(label+'-before'))
    shutil.copy2(source, target)
helper.chmod(0o755)
settings.parent.mkdir(parents=True, exist_ok=True)
settings.write_bytes(text.encode('utf-8'))
print('Editor integration installed. Backup:', backup)
