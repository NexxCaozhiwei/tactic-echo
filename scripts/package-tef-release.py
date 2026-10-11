"""Package TEF + same-commit TEK, full source and public SHA256 checksums."""
import argparse
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEF = ROOT / 'TACTIC-ECHO-FOREVER'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tek-exe', required=True, type=Path)
    parser.add_argument('--tek-manifest', required=True, type=Path)
    parser.add_argument('--smoke-evidence', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/tef/release')
    args = parser.parse_args()
    version = (TEF / 'VERSION').read_text().strip()
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip(), 'Commit source before release packaging'
    manifest = json.loads(args.tek_manifest.read_text(encoding='utf-8-sig'))
    smoke = json.loads(args.smoke_evidence.read_text(encoding='utf-8'))
    assert manifest['sourceCommit'].strip() == commit
    assert manifest['sha256'] == sha(args.tek_exe) == smoke['exe_sha256']
    assert smoke['startup_alive'] and smoke['auto_start_disabled']
    args.output.mkdir(parents=True, exist_ok=True)
    import importlib.util
    spec = importlib.util.spec_from_file_location('tef_delivery', TEF / 'scripts/deliver.py')
    delivery = importlib.util.module_from_spec(spec); spec.loader.exec_module(delivery)
    exe_manifest = {'component': 'TEK', 'release': 'tef-v' + version, 'source_commit': commit,
                    'built_at': manifest['builtAt'], 'sha256': sha(args.tek_exe), 'bytes': args.tek_exe.stat().st_size,
                    'signature_status': manifest['signatureStatus'], 'startup_smoke': 'passed_isolated_no_auto_start',
                    'sendinput_verified_this_release': False}
    bundle = args.output / f'TEF-{version}-Windows.zip'
    prefix = f'TEF-{version}/'
    with zipfile.ZipFile(bundle, 'w', zipfile.ZIP_DEFLATED) as z:
        for relative in delivery.RUNTIME:
            z.write(TEF / relative, prefix + 'TACTIC-ECHO-FOREVER/' + relative)
        z.write(args.tek_exe, prefix + 'TEK.exe')
        z.writestr(prefix + 'TEK-build-manifest.json', json.dumps(exe_manifest, ensure_ascii=False, indent=2) + '\n')
        z.write(TEF / 'docs/PRODUCTION_1.0.0.md', prefix + 'README.md')
        z.write(TEF / 'docs/RELEASE_1.0.0.md', prefix + 'RELEASE.md')
        for p in sorted((ROOT / 'examples/profiles').glob('*.json')):
            z.write(p, prefix + 'examples/' + p.name)
    with zipfile.ZipFile(bundle) as z:
        assert {n.split('/')[0] for n in z.namelist()} == {prefix.rstrip('/')}
        assert z.read(prefix + 'TEK.exe') == args.tek_exe.read_bytes()
        for relative in delivery.RUNTIME:
            assert z.read(prefix + 'TACTIC-ECHO-FOREVER/' + relative) == (TEF / relative).read_bytes()
        assert not any('/WTF/' in n or '/SavedVariables/' in n or '/logs/' in n or n.endswith('settings.json') for n in z.namelist())
    source = args.output / f'TEF-{version}-source.zip'
    subprocess.run(['git', 'archive', '--format=zip', '--prefix=' + f'TEF-{version}-source/', '--output=' + str(source.resolve()), commit], cwd=ROOT, check=True)
    subprocess.run(['python', 'scripts/verify-baseline-contract.py', '--archive', str(source.resolve()), '--expect-root', f'TEF-{version}-source'], cwd=ROOT, check=True)
    addon = ROOT / 'dist/tef' / f'TACTIC-ECHO-FOREVER-{version}.zip'
    assert addon.is_file()
    with zipfile.ZipFile(addon) as z:
        assert {n.split('/')[0] for n in z.namelist()} == {'TACTIC-ECHO-FOREVER'}
        forbidden = {'build', 'dist', 'release', '__pycache__', 'logs', 'WTF', 'SavedVariables'}
        assert not any(set(Path(n).parts) & forbidden or n.endswith(('.exe', '.log', '.jsonl', '.pyc')) for n in z.namelist())
    files = [addon, bundle, source]
    checksums = args.output / 'SHA256SUMS.txt'
    checksums.write_text(''.join(sha(p) + '  ' + p.name + '\n' for p in files), encoding='utf-8')
    receipt = args.output / 'release-receipt.json'
    receipt.write_text(json.dumps({'version': version, 'commit': commit, 'assets': [{'path': str(p), 'sha256': sha(p), 'bytes': p.stat().st_size} for p in files + [checksums]], 'tek': exe_manifest}, indent=2) + '\n', encoding='utf-8')
    print(receipt.read_text())

if __name__ == '__main__':
    main()
