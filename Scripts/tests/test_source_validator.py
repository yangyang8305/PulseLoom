"""Check default/named table resolution and ensure missing strings still fail."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('source_validator', Path(__file__).resolve().parents[1] / 'validate-source.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

class LocalizationChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.resources = Path(self.temp.name)
        for language in ['en', 'zh-Hans', 'ja']:
            folder = self.resources / (language + '.lproj')
            folder.mkdir()
            (folder / 'Localizable.strings').write_text('"default.key" = "default";\n')
            (folder / 'Recovery.strings').write_text('"recovery.key" = "recovery";\n')

    def test_named_table_resolves_without_default_table_entry(self):
        code = 'NSLocalizedString("recovery.key", tableName: "Recovery", comment: "")'
        self.assertEqual(validator.localization_failures(code, self.resources), [])

    def test_missing_default_not_masked_by_same_key_in_named_table(self):
        code = 'T("recovery.key"); NSLocalizedString("recovery.key", tableName: "Recovery", comment: "")'
        result = validator.localization_failures(code, self.resources)
        self.assertEqual(len(result), 3)
        self.assertTrue(all('Localizable.strings missing key recovery.key' in item for item in result))

    def test_nil_empty_and_omitted_table_use_default(self):
        code = '\n'.join(['T("default.key")', 'NSLocalizedString("default.key", comment: "")',
                          'NSLocalizedString("default.key", tableName: nil, comment: "")',
                          'NSLocalizedString("default.key", tableName: "", comment: "")'])
        self.assertEqual(validator.localization_failures(code, self.resources), [])

    def test_one_language_missing_is_failure(self):
        (self.resources / 'ja.lproj/Recovery.strings').write_text('')
        result = validator.localization_failures('NSLocalizedString("recovery.key", tableName: "Recovery", comment: "")', self.resources)
        self.assertEqual(result, ['ja/Recovery.strings missing key recovery.key'])

    def test_computed_table_is_not_assumed_valid(self):
        with self.assertRaisesRegex(ValueError, 'Nonliteral'):
            list(validator.localized_references('NSLocalizedString("default.key", tableName: selected, comment: "")'))

    def test_missing_table_and_duplicate_keys_are_rejected(self):
        code = 'NSLocalizedString("recovery.key", tableName: "Missing", comment: "")'
        self.assertEqual(len(validator.localization_failures(code, self.resources)), 3)
        (self.resources / 'en.lproj/Recovery.strings').write_text('"recovery.key" = "a"; "recovery.key" = "b";')
        result = validator.localization_failures('NSLocalizedString("recovery.key", tableName: "Recovery", comment: "")', self.resources)
        self.assertEqual(len(result), 1)
        self.assertIn('Duplicate', result[0])

if __name__ == '__main__':
    unittest.main()
