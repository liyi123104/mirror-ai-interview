from pypdf import PdfReader


def extract_text(source) -> str:
    """source 可以是路径，也可以是文件对象。"""
    reader = PdfReader(source)
    pages = []
    for page in reader.pages:
        pages.append(page.extract_text() or "")
    return "\n".join(pages)
