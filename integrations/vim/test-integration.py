#!/usr/bin/env python3
"""Headless editor checks using a stub helper; never changes a real input source."""
from pathlib import Path
import os, shutil, subprocess, tempfile, unittest

PLUGIN = Path(__file__).with_name('ai-bopomofo.vim').resolve()

class EditorIntegrationTests(unittest.TestCase):
    def check_editor(self, editor):
        binary = shutil.which(editor)
        if not binary:
            self.skipTest(editor + ' not installed')
        with tempfile.TemporaryDirectory(prefix='ai-vim-test-') as folder:
            root = Path(folder)
            helper = root / 'helper'
            helper.write_text('''#!/usr/bin/env python3
import os, pathlib, sys
root = pathlib.Path(os.environ['AI_VIM_TEST_DIR'])
state = root / 'state'
arg = sys.argv[1]
if arg == 'current': print(state.read_text())
else:
 with (root / 'calls').open('a') as f: f.write(arg + '\\n')
 state.write_text({'normal':'com.apple.keylayout.ABC','insert':'org.aibopomofo.inputmethod.test'}.get(arg,arg))
''')
            helper.chmod(0o700)
            (root / 'state').write_text('original.source')
            script = root / 'test.vim'
            script.write_text(f'''set belloff=all
let g:ai_bopomofo_helper = '{helper}'
source {PLUGIN}
let scripts = getscriptinfo()
let sid = filter(scripts, 'v:val.name ==# "{PLUGIN}"')[0].sid
execute 'call <SNR>' . sid . '_Apply("n")'
execute 'call <SNR>' . sid . '_Apply("i")'
execute 'call <SNR>' . sid . '_Apply("ic")'
execute 'call <SNR>' . sid . '_Apply("n")'
execute 'call <SNR>' . sid . '_Apply("R")'
execute 'call <SNR>' . sid . '_Apply("c")'
execute 'call <SNR>' . sid . '_Restore()'
augroup AIBopomofoModes
 autocmd!
augroup END
qa!
''')
            args = [binary, '-u', 'NONE', '-n']
            args += ['--headless'] if editor == 'nvim' else ['-es', '-V1'+str(root/'vim.log')]
            result = subprocess.run(args + ['-S', str(script)], env={**os.environ, 'AI_VIM_TEST_DIR': folder}, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertEqual((root/'calls').read_text().splitlines(), ['normal','insert','normal','insert','normal','original.source'])
    def test_vim(self): self.check_editor('vim')
    def test_neovim(self): self.check_editor('nvim')

if __name__ == '__main__': unittest.main()
