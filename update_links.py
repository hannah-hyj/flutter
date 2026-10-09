import re
import sys

def process_file(filename):
    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()

    # Regex to match the absolute path prefix. 
    pattern1 = r'file:///Users/jinhangyu/Documents/GitHub/flutter/packages/flutter/lib/src/'
    content = re.sub(pattern1, '', content)
    
    pattern2 = r'file:///Users/jinhangyu/Documents/GitHub/flutter/'
    content = re.sub(pattern2, '', content)

    with open(filename, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f"Updated {filename}")

files = [
    'text_plugins_design_doc.md',
    'text_plugins_design_doc_zh.md',
    'Text-Plugins-One-Pager.md'
]

for f in files:
    try:
        process_file(f)
    except Exception as e:
        print(f"Error on {f}: {e}")

