#!/usr/bin/env python3
"""
Scrape shaders from godotshaders.com and save to JSON.
This runs via GitHub Actions once daily.
"""

import json
import re
import time
import os
from datetime import datetime, timezone
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

BASE_URL = "https://godotshaders.com"
SHADERS_URL = "https://godotshaders.com/shader/"
OUTPUT_FILE = "data/shaders.json"
PAGES_TO_FETCH = 52
REQUEST_DELAY = 0.5  # Be nice to the server

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.5",
}

def fetch_page(url: str) -> str:
    """Fetch a page with proper headers."""
    response = requests.get(url, headers=HEADERS, timeout=30)
    response.raise_for_status()
    return response.text

def parse_shader_card(article) -> dict:
    """Parse a single shader card (article element)."""
    shader = {}
    
    # Get main link
    link = article.select_one("a.gds-shader-card__link")
    if not link:
        return None
    
    shader["url"] = link.get("href", "")
    if not shader["url"] or "/shader/" not in shader["url"]:
        return None
    
    # Title
    title_elem = article.select_one(".gds-shader-card__title")
    if title_elem:
        shader["title"] = title_elem.get_text(strip=True)
    else:
        return None
    
    # Author
    author_elem = article.select_one(".gds-shader-card__author")
    if author_elem:
        shader["author"] = author_elem.get_text(strip=True)
    else:
        shader["author"] = "Unknown"
    
    # Cover image (from background-image style)
    cover = article.select_one(".gds-shader-card__cover")
    if cover:
        style = cover.get("style", "")
        match = re.search(r'url\(([^)]+)\)', style)
        if match:
            shader["image_url"] = match.group(1)
    
    # Category/Type (SPATIAL, CANVAS ITEM, etc.)
    type_elem = article.select_one(".gds-shader-card__type")
    if type_elem:
        shader["category"] = type_elem.get_text(strip=True).upper()
    else:
        shader["category"] = ""
    
    # Likes (from stats - specifically the first stat-num which is likes)
    like_stat = article.select_one(".gds-shader-card__like .gds-shader-card__stat-num")
    if like_stat:
        shader["likes"] = like_stat.get_text(strip=True)
    else:
        shader["likes"] = "0"
    
    # Default license (actual license is on detail page)
    shader["license"] = "CC0"
    
    return shader

def scrape_all_shaders() -> list:
    """Scrape all shader pages."""
    all_shaders = []
    seen_urls = set()
    
    for page in range(1, PAGES_TO_FETCH + 1):
        if page == 1:
            url = SHADERS_URL
        else:
            url = f"{SHADERS_URL}page/{page}/"
        
        print(f"Fetching page {page}/{PAGES_TO_FETCH}: {url}")
        
        try:
            html = fetch_page(url)
            soup = BeautifulSoup(html, "html.parser")
            
            # Find shader cards (article elements)
            articles = soup.select("article.gds-shader-card")
            page_count = 0
            
            for article in articles:
                shader = parse_shader_card(article)
                if shader and shader.get("title") and shader.get("url"):
                    # Avoid duplicates
                    if shader["url"] not in seen_urls:
                        seen_urls.add(shader["url"])
                        all_shaders.append(shader)
                        page_count += 1
            
            print(f"  Found {page_count} shaders, total: {len(all_shaders)}")
            
            # Check if we've reached the last page
            if len(articles) == 0:
                print(f"  No more shaders, stopping at page {page}")
                break
                
        except Exception as e:
            print(f"  Error on page {page}: {e}")
        
        # Be nice to the server
        time.sleep(REQUEST_DELAY)
    
    return all_shaders

def main():
    print("Starting shader scrape...")
    now = datetime.now(timezone.utc)
    print(f"Date: {now.isoformat()}")
    
    shaders = scrape_all_shaders()
    
    print(f"\nTotal shaders scraped: {len(shaders)}")
    
    # Ensure output directory exists
    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
    
    # Save to JSON
    data = {
        "timestamp": int(now.timestamp()),
        "date": now.isoformat(),
        "count": len(shaders),
        "shaders": shaders
    }
    
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    
    print(f"Saved to {OUTPUT_FILE}")

if __name__ == "__main__":
    main()
