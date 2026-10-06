import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import rbxgrab


class ParsePlaceId(unittest.TestCase):
    def test_url(self):
        self.assertEqual(rbxgrab.parse_place_id("https://www.roblox.com/games/1818/Classic-Crossroads"), 1818)

    def test_url_locale(self):
        self.assertEqual(rbxgrab.parse_place_id("https://www.roblox.com/fr/games/920587237/Adopt-Me"), 920587237)

    def test_query(self):
        self.assertEqual(rbxgrab.parse_place_id("https://www.roblox.com/games/start?placeId=42"), 42)

    def test_number(self):
        self.assertEqual(rbxgrab.parse_place_id(" 606849621 "), 606849621)

    def test_invalid(self):
        with self.assertRaises(ValueError):
            rbxgrab.parse_place_id("https://example.com")


if __name__ == "__main__":
    unittest.main()
