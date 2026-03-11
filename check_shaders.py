import json

with open('data/shaders.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

shaders = data.get('shaders', data)
print(f'Total: {len(shaders)} shaders')

# Find shaders starting with quotes or brackets
special = [s for s in shaders if s.get('title', '').startswith('"') or s.get('title', '').startswith('[')]
print(f'\nShaders starting with " or [:')
for s in special:
    print(f"  {s.get('title')} | img: {s.get('image_url', 'NONE')[:60]}...")
