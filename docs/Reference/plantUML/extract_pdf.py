#!/usr/bin/env python3
"""
Extract PlantUML Language Reference Guide (Chinese) PDF to chapter-based markdown files.

Structure:
- Pages 579-593 = Table of Contents (skip during main extraction)
- Pages 1-578 = Actual content across ~21 chapters
- Each page ends with 2 lines: doc title header + "X / 592" page number

Output: Reference/plantUML/chNN_title.md for each chapter + Reference/plantUML/README.md
"""

import fitz
import re
import os
import sys
from collections import OrderedDict

PDF_PATH = "Reference/plantUML/PlantUML_Language_Reference_Guide_zh.pdf"
OUTPUT_DIR = "Reference/plantUML"


# ── Chapter boundaries (page ranges, 1-indexed) ──
# Manually verified from structure analysis
CHAPTERS = [
    (1, 1,     "00", "封面与介绍"),
    (2, 46,    "01", "序列图"),
    (47, 59,   "02", "用例图"),
    (60, 102,  "03", "类图"),
    (103, 109, "04", "对象图"),
    (110, 119, "05", "活动图（旧语法）"),
    (120, 160, "06", "活动图（新语法）"),
    (161, 176, "07", "组件图"),
    (177, 225, "08", "部署图"),
    (226, 248, "09", "状态图"),
    (249, 277, "10", "定时图"),
    (278, 291, "11", "JSON数据显示效果图"),
    (292, 298, "12", "YAML显示效果图"),
    (299, 327, "13", "网络图(nwdiag)"),
    (328, 347, "14", "线框图形界面(Salt)"),
    (348, 356, "15", "架构图(Archimate)"),
    (357, 396, "16", "甘特图"),
    (397, 412, "17", "思维导图(MindMap)"),
    (413, 424, "18", "工作分解结构(WBS)"),
    (425, 426, "19", "数学"),
    (427, 429, "20", "实体关系图(ER)"),
    (430, 475, "21", "通用命令"),
    (476, 509, "22", "Creole"),
    (510, 515, "23", "精灵图(Sprite)"),
    (516, 526, "24", "外观参数(Skinparam)"),
    (527, 547, "25", "预处理"),
    (548, 550, "26", "Ditaa"),
    (551, 578, "27", "标准库(StdLib)"),
    (579, 593, "28", "附录-目录索引"),
]


def clean_page_text(text: str) -> str:
    """
    Clean a page of text:
    1. Remove trailing empty lines
    2. Remove footer: "PlantUML 语言参考指引(1.2025.0)" + "X / 592"
    3. Remove page header repeats (e.g., section number repeated as page header)
    """
    lines = text.rstrip('\n').split('\n')
    
    # Remove trailing empty lines
    while lines and lines[-1].strip() == '':
        lines.pop()
    
    # Remove the last two footer lines: doc title + page number
    # Pattern: last line is "X / 592" (or similar), second-to-last is the doc reference
    cleaned = []
    skip_footer_count = 0
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        
        # Skip the doc reference header line
        if "PlantUML 语言参考指引" in stripped:
            skip_footer_count += 1
            continue
        
        # Skip "X / 592" page number line (only if preceded by doc reference header)
        if re.match(r'^\d+\s*/\s*\d+$', stripped):
            # Check if previous line was the doc reference (already skipped)
            if i > 0 and "PlantUML 语言参考指引" in lines[i-1]:
                skip_footer_count += 1
                continue
        
        cleaned.append(line)
    
    return '\n'.join(cleaned)


def extract_chapter(doc, start_page: int, end_page: int, ch_num: str, ch_title: str) -> str:
    """Extract pages for a chapter and return as cleaned markdown text."""
    pages_text = []
    
    for i in range(start_page - 1, end_page):
        text = doc[i].get_text()
        cleaned = clean_page_text(text)
        if cleaned.strip():
            pages_text.append(cleaned)
    
    raw = '\n\n'.join(pages_text)
    
    # ── Post-processing: Remove page-level header repetitions ──
    #
    # The PDF has a repeating header pattern at the top of each new section page:
    #   X.Y        <- section number
    #   section_title  <- section title
    #   N          <- chapter number (page header)
    #   diagram_type <- diagram type (page header)
    #
    # This pattern repeats the section info and chapter info at every page break.
    # We need to remove all occurrences EXCEPT the first one (which is the actual section header).
    
    # Strategy: Collect all section headers from the content, keep only first occurrence
    # of each unique section header.
    
    # First: Normalize the content - ensure consistent paragraph breaks
    raw = re.sub(r'\n{4,}', '\n\n', raw)
    
    # Define known diagram type names (page header suffixes to remove)
    diagram_types = [
        '序列图', '用例图', '类图', '对象图', '活动图', '组件图',
        '部署图', '状态图', '定时图', '甘特图', '思维导图',
        'JSON 数据', 'YAML 数据', '网络图', '线框图形界面',
        '架构图', '规范和描述语言', 'Ditaa diagram',
        'MindMap diagram', 'Entity Relationship diagram',
        'JSON Data', 'YAML Data', 'Network diagram', 'nwdiag',
        '组成部分', '部署部分', '状态部分',
    ]
    
    # Pattern to match: optional `N\n` (chapter page header) followed by a diagram type
    # This appears after a section heading (X.Y\nsection_title) as a page header artifact
    page_header_pattern = r'(?<=\d\.\d[^\n]*\n[^\n]*)\n'  # after section header + title
    
    # Remove every occurrence of a standalone `N\ndiagram_type` line (page header) that is NOT
    # the very first line of the document (i.e., not the chapter heading)
    lines = raw.split('\n')
    cleaned_lines = []
    skip_next_page_header = False
    
    for idx, line in enumerate(lines):
        stripped = line.strip()
        
        # Skip `N\ndiagram_type` patterns where N is a digit chapter number
        # Check if current line is a diagram type that appears as a page header
        is_diagram_header = stripped in diagram_types
        
        if is_diagram_header:
            # Check if previous line is a single digit (chapter number in page header)
            prev_line = lines[idx - 1].strip() if idx > 0 else ''
            is_prev_chapter_num = prev_line.isdigit() and 1 <= int(prev_line) <= 28
            
            # Also check if the line BEFORE that was part of the actual section content
            # If this is a page header repeat, skip it (and the chapter number line if present)
            if is_prev_chapter_num:
                # Check if this looks like a page header (not the actual chapter heading)
                # The actual chapter heading would appear at or near the start of the file
                if idx > 3:  # Not at start of file
                    skip_next_page_header = True
                    continue  # Skip the diagram_type line
            
            if skip_next_page_header:
                skip_next_page_header = False
                continue  # Skip this line (it's the chapter number we would have already skipped)
        
        if skip_next_page_header:
            skip_next_page_header = False
            continue
        
        cleaned_lines.append(line)
    
    # Second pass: Remove duplicate section headers
    # Pattern: "X.Y\nsection_title" appearing twice in a row
    # where the second occurrence is the page header repeat
    raw2 = '\n'.join(cleaned_lines)
    
    # Try removing any standalone `N\ndiagram_type\nN\ndiagram_type` that serves as page header padding
    # between sections
    for dt in diagram_types:
        for n in range(1, 28):
            # Pattern: "N\ndt" where it appears BETWEEN content (not at start)
            raw2 = re.sub(
                rf'(?<=\n)\b{n}\b\n{re.escape(dt)}\n(?=[\d])',
                '', raw2
            )
    
    # Third pass: aggressive dedup of page header patterns
    # Find `X.Y\ntitle\nN\ndiagram_type` that IS a page header when it appears AFTER @enduml or other content
    # and the SAME `X.Y\ntitle` also appears as the actual section start
    seen_section_headers = set()
    lines = raw2.split('\n')
    final_lines = []
    
    for idx, line in enumerate(lines):
        stripped = line.strip()
        
        # Check if this line starts a section header pattern like "X.Y"
        section_match = re.match(r'^(\d+\.\d+)$', stripped)
        
        if section_match:
            section_num = section_match.group(1)
            # Next line should be the section title
            if idx + 1 < len(lines):
                next_stripped = lines[idx + 1].strip()
                # If section title is not a diagram type or chapter number
                if next_stripped and next_stripped not in diagram_types and not (next_stripped.isdigit() and 1 <= int(next_stripped) <= 28):
                    section_key = f"{section_num}|{next_stripped}"
                    
                    # Check if we've seen this section before
                    if section_key in seen_section_headers:
                        # This is a page header repeat - skip it
                        # Also check for the trailing "N\ndiagram_type" page header
                        skip_count = 0
                        if idx + 2 < len(lines):
                            l2 = lines[idx + 2].strip()
                            if l2.isdigit() and 1 <= int(l2) <= 28:
                                skip_count += 1
                                if idx + 3 < len(lines):
                                    l3 = lines[idx + 3].strip()
                                    if l3 in diagram_types:
                                        skip_count += 1
                        
                        # Skip this section header + page header lines
                        idx += skip_count
                        continue
                    else:
                        seen_section_headers.add(section_key)
        
        final_lines.append(line)
    
    raw = '\n'.join(final_lines)
    
    # ── Final cleanup ──
    raw = raw.strip()
    
    # Normalize whitespace
    raw = re.sub(r'\n{4,}', '\n\n\n', raw)
    raw = re.sub(r'([^\n])\n(@startuml)', r'\1\n\n\2', raw)
    
    return raw


def format_markdown(content: str, ch_num: str, ch_title: str) -> str:
    """Format extracted content as proper markdown."""
    md = f"# {ch_title}\n\n"
    
    # Remove leading `N\n<diagram_type>` or `N\n<diagram_type>\nN\n<diagram_type>` 
    # duplicate that appears at the page boundary between the chapter heading and content
    content = re.sub(
        r'^\d+\n[^\n]+(?:\n\d+\n[^\n]+)?\n',
        '', content
    )
    
    md += content
    
    return md


def main():
    doc = fitz.open(PDF_PATH)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    chapter_files = []
    
    for start, end, ch_num, ch_title in CHAPTERS:
        if start > doc.page_count:
            continue
        
        actual_end = min(end, doc.page_count)
        
        print(f"  Extracting Chapter {ch_num}: {ch_title} (pages {start}-{actual_end})")
        
        content = extract_chapter(doc, start, actual_end, ch_num, ch_title)
        md = format_markdown(content, ch_num, ch_title)
        
        # Sanitize title for filename
        safe_title = re.sub(r'[\\/:*?"<>|]', '', ch_title)
        safe_title = safe_title.replace(' ', '_')
        
        filename = f"ch{ch_num}_{safe_title}.md"
        filepath = os.path.join(OUTPUT_DIR, filename)
        
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(md)
        
        chapter_files.append((ch_num, ch_title, filename))
    
    # ── Generate README.md with table of contents ──
    readme_lines = [
        "# PlantUML 语言参考指引",
        "",
        "本文档由 [PlantUML_Language_Reference_Guide_zh.pdf](./PlantUML_Language_Reference_Guide_zh.pdf) 自动提取生成。",
        "",
        "版本: 1.2025.0",
        "",
        "## 目录",
        "",
        "| 章节 | 标题 | 文件 |",
        "|------|------|------|",
    ]
    
    for ch_num, ch_title, filename in chapter_files:
        readme_lines.append(f"| {ch_num} | {ch_title} | [{filename}](./{filename}) |")
    
    readme_path = os.path.join(OUTPUT_DIR, "README.md")
    with open(readme_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(readme_lines))
    
    print(f"\n✓ Done! Generated {len(chapter_files)} markdown files + README.md")
    
    doc.close()


if __name__ == "__main__":
    main()