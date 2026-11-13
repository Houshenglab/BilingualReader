"""Bundle the isolated runtime and parser; no runtime dependency on Codex or system Python."""
import importlib.metadata
import pathlib
import shutil
import sys

root = pathlib.Path(__file__).resolve().parents[1]
target = root / 'Resources/PDFEngine/python'
version = f'python{sys.version_info.major}.{sys.version_info.minor}'
stdlib = pathlib.Path(sys.prefix) / 'lib' / version
site = stdlib / 'site-packages'
ignore = shutil.ignore_patterns('__pycache__', '*.pyc', 'site-packages', 'test', 'tests', 'idlelib', 'tkinter', 'turtledemo', 'ensurepip')
(target / 'bin').mkdir(parents=True, exist_ok=True)
shutil.copy2(sys.executable, target / 'bin/python3')
shutil.copytree(stdlib, target / 'lib' / version, dirs_exist_ok=True, ignore=ignore)
packages = target / 'lib' / version / 'site-packages'
packages.mkdir(exist_ok=True)
for name in ['pdfminer', 'cryptography', 'charset_normalizer', 'cffi', 'pycparser']:
    shutil.copytree(site / name, packages / name, dirs_exist_ok=True, ignore=shutil.ignore_patterns('__pycache__', '*.pyc', 'tests'))
for module in site.glob('_cffi_backend*.so'):
    shutil.copy2(module, packages / module.name)
versions = {'Python': sys.version.split()[0]}
for name in ['pdfminer.six', 'cryptography', 'charset-normalizer', 'cffi', 'pycparser']:
    dist = importlib.metadata.distribution(name)
    versions[name] = dist.version
    metadata_dir = pathlib.Path(dist._path)
    shutil.copytree(metadata_dir, packages / metadata_dir.name, dirs_exist_ok=True)
(root / 'Resources/PDFEngine/VERSIONS.txt').write_text('\n'.join(f'{k} {v}' for k, v in versions.items()) + '\n')
print('Bundled isolated PDF parser:', versions)
