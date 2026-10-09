import re

def move_spellcheck_en():
    with open('text_plugins_design_doc.md', 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Remove from Framework Builtin
    content = re.sub(r'3\. \*\*`DefaultSpellCheckPlugin`\*\*.*?lines\.\n\n', '\n', content)
    
    # Add to Community Packages
    community_marker = "#### 2.2.2 Community Package Plugins (`pub.dev`)\n\nDomain-specific, opinionated, or third-party-dependent features should be maintained by the community as standalone packages:\n\n"
    
    insert_str = "1. **`SpellCheckPlugin` (`package:flutter_spellcheck`)**: Integration for IME spellcheck squiggly underlines and grammar suggestions.\n"
    
    content = content.replace(community_marker, community_marker + insert_str)
    
    # Renumber the community list (they start with 1, 2, 3...)
    # Actually, if we just insert it as 1. and let the others be 1. 2. 3. 4. 5. 6., markdown automatically fixes it on render.
    # But it's cleaner to just fix the numbers using regex.
    # We can just change 1 to 2, 2 to 3, etc.
    # A quick way:
    # We replaced community_marker, let's just write a custom renumbering function for the list block.
    # Easier: just change the numbers manually in the string.
    
    with open('text_plugins_design_doc.md', 'w', encoding='utf-8') as f:
        f.write(content)

def move_spellcheck_zh():
    with open('text_plugins_design_doc_zh.md', 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Remove from Framework Builtin
    content = re.sub(r'3\. \*\*`DefaultSpellCheckPlugin`\*\*.*?\n\n', '\n', content)
    
    # Add to Community Packages
    community_marker = "#### 2.2.2 社区 Package 插件 (`pub.dev`)\n\n特定领域、带有业务偏向或依赖第三方库的功能应当由社区作为独立 Package 维护：\n\n"
    
    insert_str = "1. **`SpellCheckPlugin` (`package:flutter_spellcheck`)**：对接原生 IME 拼写检查与波浪线错误提示。\n"
    
    content = content.replace(community_marker, community_marker + insert_str)
    
    with open('text_plugins_design_doc_zh.md', 'w', encoding='utf-8') as f:
        f.write(content)

move_spellcheck_en()
move_spellcheck_zh()
