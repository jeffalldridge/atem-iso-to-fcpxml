"""Static publishing contracts; no network or browser dependency in CI."""
import json
import struct
import unittest
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit

SITE = Path(__file__).resolve().parents[1] / "docs" / "site"
URL = "https://jeffalldridge.github.io/atem-iso-to-fcpxml/"


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.refs, self.headings, self.metas, self.links = [], [], [], {}, {}
        self.schema, self.text = "", []
        self.in_schema = False
        self.faqs = []
        self.part = None
        self.question = self.answer = ""
        self.in_article = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            self.ids.append(a["id"])
        if "aria-labelledby" in a:
            self.refs.extend("#" + value for value in a["aria-labelledby"].split())
        if tag in ("a", "link") and "href" in a:
            self.refs.append(a["href"])
        if tag == "link":
            self.links[a.get("rel")] = a.get("href")
        if tag == "meta":
            self.metas[a.get("name", a.get("property"))] = a.get("content")
        if tag == "h1":
            self.headings.append(tag)
        if tag == "script":
            self.in_schema = a.get("type") == "application/ld+json"
        if tag == "article":
            self.in_article = "answer" in a.get("class", "").split()
            self.question = self.answer = ""
        if self.in_article and tag in ("h3", "p"):
            self.part = tag

    def handle_endtag(self, tag):
        if tag == "script":
            self.in_schema = False
        if tag in ("h3", "p"):
            self.part = None
        if tag == "article" and self.in_article:
            self.faqs.append((self.question, self.answer))
            self.in_article = False

    def handle_data(self, data):
        if self.in_schema:
            self.schema += data
        else:
            self.text.append(data)
        if self.part == "h3":
            self.question += data
        elif self.part == "p":
            self.answer += data


class SiteTests(unittest.TestCase):
    def setUp(self):
        self.page = Page()
        self.page.feed((SITE / "index.html").read_text())
        self.graph = json.loads(self.page.schema)["@graph"]

    def test_canonical_and_social_metadata(self):
        p = self.page
        self.assertEqual(p.links["canonical"], URL)
        self.assertEqual(p.metas["og:url"], URL)
        self.assertEqual(p.metas["twitter:card"], "summary_large_image")
        self.assertEqual(p.metas["og:image"], p.metas["twitter:image"])
        self.assertTrue(p.metas["og:image:alt"])
        self.assertNotIn("noindex", p.metas["robots"])
        image = SITE / p.metas["og:image"].removeprefix(URL)
        raw = image.read_bytes()
        self.assertEqual(raw[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(struct.unpack(">II", raw[16:24]), (1200, 630))
        self.assertLess(len(raw), 500000)

    def test_local_links_and_accessible_references(self):
        self.assertEqual(len(self.page.ids), len(set(self.page.ids)))
        self.assertEqual(len(self.page.headings), 1)
        for ref in self.page.refs:
            with self.subTest(ref=ref):
                parsed = urlsplit(ref)
                if parsed.scheme or parsed.netloc:
                    continue
                if parsed.path and parsed.path != "./":
                    self.assertTrue((SITE / parsed.path).is_file())
                if parsed.fragment:
                    self.assertIn(parsed.fragment, self.page.ids)

    def test_schema_faq_matches_readable_content(self):
        faq = next(node for node in self.graph if node["@type"] == "FAQPage")
        for question in faq["mainEntity"]:
            self.assertIn((question["name"], question["acceptedAnswer"]["text"]), self.page.faqs)
        self.assertEqual(len(faq["mainEntity"]), len(self.page.faqs))

    def test_schema_graph_references_resolve(self):
        ids = {node["@id"] for node in self.graph}
        self.assertEqual(len(ids), len(self.graph))
        def walk(value):
            if isinstance(value, dict):
                if set(value) == {"@id"}:
                    self.assertIn(value["@id"], ids)
                for child in value.values():
                    walk(child)
            elif isinstance(value, list):
                for child in value:
                    walk(child)
        walk(self.graph)
        app = next(node for node in self.graph if node["@type"] == "SoftwareApplication")
        self.assertEqual(app["offers"]["price"], "0")
        self.assertNotIn("aggregateRating", app)  # No invented review evidence.

    def test_sitemap_and_plain_text_reference(self):
        tree = ET.parse(SITE / "sitemap.xml")
        locations = [n.text for n in tree.findall(".//{*}loc")]
        self.assertEqual(locations, [URL])
        reference = (SITE / "llms.txt").read_text()
        self.assertIn("docs/validation.md", reference)
        self.assertIn("not a crawler policy", reference)
