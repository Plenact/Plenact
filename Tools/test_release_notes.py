"""Regression coverage for curated release-note extraction."""

import unittest

from release_notes import entries


class ReleaseNotesTests(unittest.TestCase):
    def test_sections_do_not_leak_into_adjacent_releases(self):
        sections = entries(
            '# History\n\n## Unreleased\n\n- Future only\n\n'
            '## v1.1 — 2026-10-18\n\n### Added\n\n- New release only\n\n'
            '## v1.0 — 2026-10-16\n\n### Fixed\n\n- Old release only\n'
        )
        self.assertEqual(sections['v1.1'][0], '2026-10-18')
        self.assertIn('New release only', sections['v1.1'][1])
        self.assertNotIn('Future only', sections['v1.1'][1])
        self.assertNotIn('Old release only', sections['v1.1'][1])

    def test_duplicate_versions_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            entries('## v1.0 — 2026-10-16\n- One\n## v1.0 — 2026-10-16\n- Two\n')

    def test_missing_or_invalid_dates_are_rejected(self):
        for heading in ['## v1.0', '## v1.0 — 2026-02-30']:
            with self.subTest(heading=heading), self.assertRaises(ValueError):
                entries(heading + '\n- A change\n')

    def test_empty_version_notes_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Missing release details'):
            entries('## v1.0 — 2026-10-16\n\n### Added\n')


if __name__ == '__main__':
    unittest.main()
