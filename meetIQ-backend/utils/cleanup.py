from pathlib import Path


def cleanup_file(file_path: str) -> None:
    if not file_path:
        return
    try:
        path = Path(file_path)
        if path.exists():
            path.unlink(missing_ok=True)
        parent = path.parent
        if parent.exists() and parent.is_dir() and not any(parent.iterdir()):
            parent.rmdir()
    except Exception:
        pass
