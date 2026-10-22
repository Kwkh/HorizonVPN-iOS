#!/usr/bin/env python3
"""Offline safety checks; never invokes PlugInKit or changes VPN state."""
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('preparation', Path(__file__).with_name('prepare-macos-extension.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name).resolve() / 'HorizonMac.app'
        self.target = self.app / 'Contents/PlugIns/HorizonMacTunnel.appex'
        self.old = Path(self.directory.name).resolve() / 'Old.app/Contents/PlugIns/HorizonMacTunnel.appex'
        self.target.mkdir(parents=True)
        self.old.mkdir(parents=True)
        self.calls = []
        self.paths = [self.old]
        self.active = False
        self.inject_failure = False

    def run_tool(self, *args):
        self.calls.append(args)
        if args[0].endswith('scutil'):
            return f'({"Connected" if self.active else "Disconnected"}) Horizon [VPN:Kenote.Clash]'
        if args[0].endswith('pluginkit'):
            if args[1] == '-m':
                return ''.join(f' Path = {p}\n' for p in self.paths)
            if args[1] == '-a':
                p = Path(args[2])
                if p not in self.paths:
                    self.paths.append(p)
            if args[1] == '-r':
                if self.inject_failure:
                    self.inject_failure = False
                    raise RuntimeError('Injected registry failure')
                self.paths.remove(Path(args[2]))
        return ''

    def invoke(self, apply=True, wrong_id=False):
        def identity(p):
            if wrong_id:
                return 'other.vpn'
            return module.EXT_ID if p.suffix == '.appex' else module.APP_ID
        with patch('sys.argv', ['prepare', '--app', str(self.app)] + (['--apply'] if apply else [])), \
             patch.object(module, 'run', self.run_tool), patch.object(module, 'bundle_id', identity):
            module.main()

    def test_dry_run_does_not_mutate(self):
        self.invoke(False)
        self.assertEqual(self.paths, [self.old])
        self.assertFalse(any(c[1] in ('-a', '-r', '-f') for c in self.calls))

    def test_active_vpn_skips_mutations(self):
        self.active = True
        self.invoke()
        self.assertEqual(self.paths, [self.old])
        self.assertFalse(any(c[1] in ('-a', '-r', '-f') for c in self.calls))

    def test_wrong_bundle_rejected(self):
        with self.assertRaises(RuntimeError):
            self.invoke(wrong_id=True)
        self.assertEqual(self.calls, [])

    def test_selection_is_idempotent_and_scoped(self):
        self.invoke()
        self.invoke()
        self.assertEqual(self.paths, [self.target])
        self.assertTrue(all(module.EXT_ID in c for c in self.calls if c[1] == '-m'))

    def test_failure_restores_previous_registration(self):
        self.inject_failure = True
        with self.assertRaises(RuntimeError):
            self.invoke()
        self.assertEqual(self.paths, [self.old])


if __name__ == '__main__':
    unittest.main()
