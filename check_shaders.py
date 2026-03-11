import json

with open('data/shaders.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

shaders = data.get('shaders', data)

# Find Hand Drawn shader and show char codes
for s in shaders:
    if 'Hand Drawn' in s.get('title', ''):
        title = s['title']
        print(f"Title: {title}")
        print(f"First 5 chars hex: {[hex(ord(c)) for c in title[:5]]}")
        break
