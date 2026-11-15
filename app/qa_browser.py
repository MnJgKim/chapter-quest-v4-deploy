"""Portable isolated browser launcher; never installs tools or changes user profiles."""
import os
from pathlib import Path
from shutil import which


def launch_browser(playwright, **options):
    explicit = os.environ.get('CQ_CHROMIUM_PATH')
    bundled = Path(playwright.chromium.executable_path)
    executable = explicit or (None if bundled.is_file() else which('chromium') or which('chromium-browser'))
    if explicit and not Path(explicit).is_file():
        raise RuntimeError('CQ_CHROMIUM_PATH does not identify an installed browser')
    if not executable and not bundled.is_file():
        raise RuntimeError('Install Playwright Chromium or set CQ_CHROMIUM_PATH to an existing browser')
    if executable:
        options['executable_path'] = executable
    return playwright.chromium.launch(**options)
